# Pre-built moab-balance SD image

This directory contains everything needed to bake a ready-to-flash Raspberry
Pi OS image that, once written to an SD card and inserted into a Project Moab
Pi, **boots straight into a balancing plate** with no SSH, no `install.sh`,
no Moabian dependency.

Under the hood it uses [`pi-gen`](https://github.com/RPi-Distro/pi-gen) (the
official Raspberry Pi OS image builder) with a custom **`stage-moab`** that
layers our package, the vendored HAT firmware, a cross-compiled
[`mcumgr`](https://github.com/apache/mynewt-mcumgr-cli) binary, and the right
Pi config on top of stock Pi OS Lite (Bookworm, 64-bit by default).

## Prerequisites

* **Docker** (Docker Desktop on macOS / Windows, or any Docker-compatible
  runtime — Colima, OrbStack, Rancher Desktop, Podman with the Docker shim).
  Pi-gen is Linux-only; the build runs entirely inside containers.
* **~25 GB of free disk** for pi-gen's working directory.
* **Network** to pull the pi-gen Docker image and the cross-compile toolchain.
* **macOS / Linux / Windows host.** First-time builds take ~30–45 minutes
  (mostly downloading apt packages inside the qemu'd chroot); incremental
  re-builds take a few minutes.

## Build

```bash
cd image
./build.sh
```

When the build finishes, the flashable image will be at:

```
image/deploy/<date>-moab-balance-lite.img.xz
```

Flash it with [Raspberry Pi Imager](https://www.raspberrypi.com/software/),
[`balena etcher`](https://etcher.balena.io/), or `xz -d <…>.img.xz | dd …`.

## What's on the image

* **Pi OS Lite (Bookworm, arm64)** — base, configured for the Moab kit:
  * `dtparam=spi=on` (HAT runtime SPI)
  * `dtoverlay=uart1` (HAT MCU bootloader UART, `/dev/ttyAMA1`)
  * `camera_auto_detect=1` (default — libcamera + V4L2 bridge for `/dev/video0`)
  * Default user `pi` / password `moab` (⚠ change with `passwd` on first boot)
  * SSH enabled
  * Hostname `moab` (`ssh pi@moab.local`)
* **`/opt/moab-balance/`** — our package, plus `firmware/v3.bin` (Microsoft's
  HAT firmware, vendored under MIT) and `firmware/flash-hat.sh`.
* **`/usr/local/bin/mcumgr`** — Apache MyNewt SMP CLI, cross-compiled for the
  target arch at build time.
* **`moab-hat-flash.service`** (systemd, oneshot) — flashes the HAT MCU on
  first boot via the GPIO bootloader dance + `mcumgr image upload`. Drops a
  marker file at `/var/lib/moab-hat-flashed` so subsequent boots skip the
  flash entirely. Retries up to 3× on failure.
* **`moab-balance.service`** (systemd) — the runtime. `Requires=` the flash
  service, so it won't start until the HAT has confirmed firmware.

## First-boot sequence

```
power on
  ↓
systemd reaches multi-user.target
  ↓
moab-hat-flash.service:                   (~30 s, only first boot)
  • drives HAT into MCUboot bootloader (GPIO 20/5/6 dance)
  • mcumgr image upload v3.bin → /dev/ttyAMA1
  • resets HAT into application mode
  • writes /var/lib/moab-hat-flashed
  ↓
moab-balance.service starts:
  • opens /dev/spidev0.0, /dev/video0
  • 30 Hz: capture → HSV detect → 2-axis PID → SET_SERVOS
  ↓
plate balances forever
```

## Configuration

Edit [`config`](./config) before running `./build.sh` to change defaults:

| Variable                        | Default                 | Purpose                                                     |
| ------------------------------- | ----------------------- | ----------------------------------------------------------- |
| `IMG_NAME`                      | `moab-balance`          | Output image base name                                      |
| `TARGET_HOSTNAME`               | `moab`                  | mDNS name → `ssh pi@moab.local`                             |
| `FIRST_USER_NAME`               | `pi`                    | Default Linux user                                          |
| `FIRST_USER_PASS`               | `moab`                  | Default password (⚠ change for production)                  |
| `ENABLE_SSH`                    | `1`                     | SSH server on by default                                    |
| `WPA_*`                         | unset                   | Set to bake WiFi creds into the image                       |
| `PIGEN_REF`                     | `2025-11-24-raspios-…`  | Pinned pi-gen tag (matches Pi OS release/arch)              |
| `MCUMGR_REF`                    | pinned commit           | Pinned `mcumgr-cli` commit                                  |
| `TARGET_GOARCH`                 | `arm64`                 | Set `arm` (and switch `PIGEN_REF` to a 32-bit branch) for Pi 3 |

## Building for Pi 3 / Pi Zero 2 (32-bit)

```bash
PIGEN_REF=2025-05-13-raspios-bookworm \
TARGET_GOARCH=arm \
TARGET_GOARM=7 \
./build.sh
```

(Make sure to use the matching tag from
<https://github.com/RPi-Distro/pi-gen/tags> — the bookworm 32-bit branch is
just `bookworm`, and pinned tags exist for known-good points.)

## Forcing a HAT re-flash

If you ever swap HATs or upgrade `firmware/v3.bin`:

```bash
sudo rm /var/lib/moab-hat-flashed
sudo systemctl restart moab-hat-flash.service
journalctl -u moab-hat-flash.service -f
```

## Reproducibility

Both pi-gen and mcumgr are pinned by SHA in `config`. The same SHA produces
the same binaries; only Debian apt mirrors can drift between builds. For
fully byte-identical reproducibility you can layer an `apt-cacher-ng` proxy
on the build host and point `APT_PROXY` at it.

## How it differs from `install.sh`

`install.sh` is the *runtime* installer for an already-running Pi (typically
the stock Moabian image). The pre-built SD image performs the same
configuration *offline* during `pi-gen`'s `qemu`'d chroot, so the very first
boot of a fresh SD already has everything in place.
