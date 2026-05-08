"""Minimal SPI driver for the Project Moab HAT.

Speaks the same 8-byte SPI protocol the stock Moabian firmware expects. Only
the three opcodes needed for ball balancing are implemented: enable servos,
disable servos, set servo positions. Everything else (LCD text, button
polling, debug pretty-printing, calibration packets) is intentionally
omitted — see microsoft/moabian for the full API.

Protocol summary (derived from microsoft/moabian/sw/hat.py — see NOTICE):

* SPI bus:        /dev/spidev0.0
* SPI clock:      100 kHz
* Frame size:     8 bytes per transaction (Pi <-> HAT, full duplex)
* GPIO pins:      HAT_EN  = BCM 20, HAT_RESET = BCM 6.
                  Setting their direction to OUT is what resets the HAT into
                  its known boot state, so we always do that on .open().
* Opcodes used here:
    0x01 SERVO_ENABLE
    0x02 SERVO_DISABLE
    0x05 SET_SERVOS    payload: s3_hi s3_lo s1_hi s1_lo s2_hi s2_lo
                       (each value is angle * 100, signed int16, big-endian)
"""

from __future__ import annotations

import time
from typing import Tuple

# These imports are Pi-only and would fail to import on a dev machine, so we
# guard them. The driver itself simply will not function without them.
try:
    import spidev  # type: ignore
    import RPi.GPIO as gpio  # type: ignore
    _HARDWARE_AVAILABLE = True
except ImportError:  # pragma: no cover - dev machines
    spidev = None  # type: ignore
    gpio = None  # type: ignore
    _HARDWARE_AVAILABLE = False


SPI_BUS = 0
SPI_DEVICE = 0
SPI_HZ = 100_000
SPI_FRAME = 8

CMD_SERVO_ENABLE = 0x01
CMD_SERVO_DISABLE = 0x02
CMD_SET_SERVOS = 0x05

PIN_HAT_EN = 20
PIN_HAT_RESET = 6

# Settle time after each SPI transaction (matches stock firmware expectation).
TRANSACTION_DELAY_S = 0.005


def _pad(*payload: int) -> list:
    """Right-pad ``payload`` with zeros to an 8-byte SPI frame."""
    if len(payload) > SPI_FRAME:
        raise ValueError(f"payload longer than {SPI_FRAME} bytes")
    return list(payload) + [0] * (SPI_FRAME - len(payload))


def _angle_to_int16_bytes(angle_deg: float) -> Tuple[int, int]:
    """Encode ``angle_deg`` as a big-endian signed int16 in centi-degrees."""
    centi = int(round(angle_deg * 100.0))
    centi = max(-32768, min(32767, centi))
    if centi < 0:
        centi += 1 << 16
    return (centi >> 8) & 0xFF, centi & 0xFF


class Hat:
    """Thin wrapper around the SPI + GPIO control of the Moab HAT."""

    def __init__(self) -> None:
        self.spi = None

    # -- lifecycle --------------------------------------------------------
    def open(self) -> None:
        if not _HARDWARE_AVAILABLE:
            raise RuntimeError(
                "spidev / RPi.GPIO not available — Hat can only run on a "
                "Raspberry Pi with the Moab HAT attached."
            )
        self.spi = spidev.SpiDev()
        self.spi.open(SPI_BUS, SPI_DEVICE)
        self.spi.max_speed_hz = SPI_HZ

        gpio.setwarnings(False)
        gpio.setmode(gpio.BCM)
        # The act of (re)setting these pins as outputs power-cycles the HAT
        # into a known state — see microsoft/moabian/sw/hat.py.
        gpio.setup([PIN_HAT_EN, PIN_HAT_RESET], gpio.OUT)
        time.sleep(0.1)

    def close(self) -> None:
        if self.spi is not None:
            try:
                self.spi.close()
            finally:
                self.spi = None

    def __enter__(self) -> "Hat":
        self.open()
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()

    # -- low-level transfer ----------------------------------------------
    def _transceive(self, frame: list) -> None:
        if self.spi is None:
            raise RuntimeError("Hat.open() has not been called")
        if len(frame) != SPI_FRAME:
            raise ValueError(f"SPI frame must be exactly {SPI_FRAME} bytes")
        self.spi.xfer(frame)
        time.sleep(TRANSACTION_DELAY_S)

    # -- public commands -------------------------------------------------
    def enable_servos(self) -> None:
        self._transceive(_pad(CMD_SERVO_ENABLE))

    def disable_servos(self) -> None:
        self._transceive(_pad(CMD_SERVO_DISABLE))

    def set_servos(self, s1_deg: float, s2_deg: float, s3_deg: float) -> None:
        """Command the three servo arms to the given absolute angles (deg).

        Wire ordering matches the firmware: payload is s3, s1, s2.
        """
        s3h, s3l = _angle_to_int16_bytes(s3_deg)
        s1h, s1l = _angle_to_int16_bytes(s1_deg)
        s2h, s2l = _angle_to_int16_bytes(s2_deg)
        self._transceive(_pad(CMD_SET_SERVOS, s3h, s3l, s1h, s1l, s2h, s2l))
