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
| `systemd/moab-balance.service`      | Systemd unit; replaces `moab.service`                     |
| `install.sh`                        | One-shot installer for the stock Moabian Pi image         |

## Hardware assumptions

* A Project Moab kit (Raspberry Pi 4, custom HAT, 3 servos, Pi Camera v2).
* The stock [Moabian](https://github.com/microsoft/moabian) Pi image as the
  starting point — it has SPI, GPIO, and the Pi Camera enabled and configured,
  and a `pi` user in the `spi` / `gpio` / `video` groups. If you flashed a
  bare Raspberry Pi OS instead, run `sudo raspi-config` and enable SPI and the
  camera before installing.

## Installing on the Pi

Copy this directory to the Pi and run the installer:

```bash
scp -r . pi@moab.local:~/moab-balance
ssh pi@moab.local
cd moab-balance
sudo ./install.sh
```

The installer will:

1. Stop and disable the stock `moab.service`.
2. Copy the package to `/opt/moab-balance`.
3. Install runtime dependencies via `apt` (`python3-opencv`, `python3-numpy`,
   `python3-rpi.gpio`, `python3-spidev`) and create a small venv.
4. Enable and start `moab-balance.service`.

After that, every reboot brings the plate up live and balancing.

```bash
journalctl -u moab-balance.service -f      # live logs
sudo systemctl restart moab-balance        # restart after editing config.py
```

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
