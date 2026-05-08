# Project Moab HAT firmware

This directory contains the binary firmware that runs on the **HAT MCU** of the
Project Moab kit (the small microcontroller on the daughterboard that drives
the three servos and reads the buttons / LCD).

| File                     | Description                                                                      |
| ------------------------ | -------------------------------------------------------------------------------- |
| `v3.bin`                 | Build 3.0 (May 2021) of Microsoft's Zephyr-based HAT firmware (112 KB).          |
| `v3.bin.sha256`          | SHA-256 of `v3.bin` for integrity checking.                                      |
| `flash-hat.sh`           | Idempotent flasher: GPIO bootloader dance + `mcumgr image upload`.               |
| `moab-hat-flash.service` | Systemd oneshot that runs the flasher on first boot and self-disables on success.|

## Provenance and licence

`v3.bin` is **vendored verbatim** from
[`microsoft/moabian/fw/v3.bin`](https://github.com/microsoft/moabian/blob/main/fw/v3.bin)
at SHA-256 `a2ad9c0c2585c3509b2b7f05c581ef16f3a5e031200096f56b88d303b870779e`.

It is distributed under the **MIT License** (Copyright © Microsoft
Corporation). See the project's top-level [`NOTICE`](../NOTICE) for the full
attribution and the [`LICENSE`](../LICENSE) under which `moab-balance` itself
is distributed (also MIT). The original Zephyr source for the firmware lives
at [`microsoft/moabian/fw/src/`](https://github.com/microsoft/moabian/tree/main/fw/src).

## What the flasher does

1. Drives the HAT into its MCUboot bootloader by toggling three GPIOs:
   - `GPIO 20` (HAT_EN), `GPIO 5` (BOOT_EN), `GPIO 6` (HAT_RESET) → output, high
   - sleep 1 s, then pull `GPIO 6` low → MCU enters bootloader
2. Uploads `v3.bin` over `/dev/ttyAMA1` at 115 200 8N1 using
   [`mcumgr`](https://github.com/apache/mynewt-mcumgr-cli) (the Apache MyNewt
   Simple Management Protocol CLI).
3. Resets the HAT into application mode by toggling the GPIOs again.
4. Drops a marker file at `/var/lib/moab-hat-flashed` so subsequent boots skip
   the flash entirely.

The flash takes ~30 seconds and only happens once per HAT (or whenever you
delete the marker file to force a re-flash).

## Forcing a re-flash

```bash
sudo rm /var/lib/moab-hat-flashed
sudo systemctl restart moab-hat-flash.service
journalctl -u moab-hat-flash.service -f
```
