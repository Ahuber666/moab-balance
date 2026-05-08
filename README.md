# moab-balance

A drop-in replacement for the stock Microsoft [Project Moab](https://github.com/microsoft/moabian)
software that does **only one thing**: balance a ball on the plate.

No menu, no LCD UI, no Bonsai brain, no calibration wizard — the Pi boots,
the plate finds level, the ball stays centred. That's it.

## What's in the box

| File / dir                          | Purpose                                                   |
| ----------------------------------- | --------------------------------------------------------- |
| `moab_balance/hat.py`               | Minimal SPI driver for the Moab HAT (3 opcodes only)      |
| `moab_balance/kinematics.py`        | Plate angle → 3 servo angles inverse kinematics           |
| `moab_balance/camera.py`            | Pi Camera capture (cv2 / V4L2)                            |
| `moab_balance/vision.py`            | HSV ball detector                                         |
| `moab_balance/controller.py`        | 2-axis PID with high-pass-filtered derivative             |
| `moab_balance/balance.py`           | The 30 Hz main loop                                       |
| `moab_balance/config.py`            | Every tunable in one dataclass                            |
| `firmware/v3.bin`                   | Project Moab HAT firmware (vendored from microsoft/moabian, MIT) |
| `firmware/flash-hat.sh`             | Idempotent HAT MCU flasher (UART + `mcumgr`)              |
| `systemd/moab-balance.service`      | Systemd unit; replaces `moab.service`                     |
| `systemd/moab-hat-flash.service`    | Oneshot that flashes the HAT firmware on first boot       |
| `install.sh`                        | One-shot installer for an already-running Pi              |
| `image/`                            | Build a flash-and-go SD image with `pi-gen` (see below)   |

## Hardware assumptions

* A Project Moab kit (Raspberry Pi 4, custom HAT, 3 servos, Pi Camera v2).
* The stock [Moabian](https://github.com/microsoft/moabian) Pi image as the
  starting point — it has SPI, GPIO, and the Pi Camera enabled and configured,
  and a `pi` user in the `spi` / `gpio` / `video` groups. If you flashed a
  bare Raspberry Pi OS instead, run `sudo raspi-config` and enable SPI and the
  camera before installing.

## Two ways to install

### A. Bake a flash-and-go SD image (recommended for fresh hardware)

`image/build.sh` produces a self-contained Pi OS image that, once flashed and
booted, balances on its own — no SSH, no manual steps. It cross-compiles
[`mcumgr`](https://github.com/apache/mynewt-mcumgr-cli), bundles the vendored
HAT firmware, and runs Microsoft's MCU bootloader sequence on first boot to
flash the HAT. See [`image/README.md`](image/README.md) for the full recipe.

```bash
cd image && ./build.sh
# → image/deploy/<date>-moab-balance-lite.img.xz
# Flash with Raspberry Pi Imager → insert SD → power on → balancing.
```

Requires Docker on your build machine. First build ~30–45 minutes; subsequent
builds reuse pi-gen's cache.

### B. Install on an already-running Pi

Copy this directory to the Pi (whether it's running stock Moabian or a fresh
Raspberry Pi OS install) and run the installer:

```bash
scp -r . pi@moab.local:~/moab-balance
ssh pi@moab.local
cd moab-balance
sudo ./install.sh
```

The installer will:

1. Stop and disable the stock `moab.service` (if present).
2. Copy the package to `/opt/moab-balance`.
3. Install runtime dependencies via `apt` (`python3-opencv`, `python3-numpy`,
   `python3-rpi.gpio`, `python3-spidev`, `raspi-gpio`) and create a small venv.
4. Enable `moab-hat-flash.service` (oneshot, flashes the HAT MCU on next boot
   if not already done) and `moab-balance.service`.

After that, every reboot brings the plate up live and balancing.

```bash
journalctl -u moab-balance.service -f      # live logs
sudo systemctl restart moab-balance        # restart after editing config.py
```

> **Note:** if you install on a *bare* Pi OS (not the stock Moabian image),
> you'll also need `mcumgr` at `/usr/local/bin/mcumgr` for the HAT firmware
> flash to work. The pre-built SD image (option A) handles this for you. To
> install `mcumgr` manually on a Pi: `go install
> github.com/apache/mynewt-mcumgr-cli/mcumgr@latest && sudo cp ~/go/bin/mcumgr
> /usr/local/bin/`.

## Tuning

Everything you can change lives in [`moab_balance/config.py`](moab_balance/config.py).
The most common things you'll touch:

### Ball colour (HSV thresholds)

The defaults are tuned for the orange ping-pong ball that ships with the
Moab kit. If you swap balls, change `hsv_low` / `hsv_high`. OpenCV's hue
range is `0..179`. Note that if your ball is red you'll want a wrap-around
range like `hsv_low=(170, 120, 100)`, `hsv_high=(10, 255, 255)` — the
detector handles the wrap automatically.

A quick way to find good values: SSH to the Pi, stop the service, and use
any HSV picker on a saved frame (or run the detector with `log_every_n_frames=1`
and adjust until detections are stable).

### PID gains

`kp=75`, `ki=0.5`, `kd=45`, `max_angle_deg=16` are Microsoft's stock values
and work well on a stock kit. If your ball oscillates, drop `kp` first
(say to 60) and only then nudge `kd` up. If it's sluggish to recentre,
nudge `kp` up by 10–20% at a time.

### Per-unit servo trim

The three servos on every Moab are slightly different. The factory prints
three small numbers inside the lid of the kit — copy them into
`servo_offsets=(o1, o2, o3)` for a level plate at rest. If you don't have
those numbers, leave them at `(0, 0, 0)`; the plate will still balance,
just with a small steady-state offset.

## Restoring the stock software

Nothing is overwritten — the stock Moabian software is just disabled.

```bash
sudo systemctl disable --now moab-balance.service
sudo systemctl enable  --now moab.service
```

## Licence

MIT, see [LICENSE](LICENSE). Portions of the SPI protocol details and the
plate inverse-kinematics formula are derived from
[microsoft/moabian](https://github.com/microsoft/moabian) (also MIT) — see
[NOTICE](NOTICE) for the attribution.
