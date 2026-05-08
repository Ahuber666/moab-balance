#!/usr/bin/env bash
# Flash the Project Moab HAT MCU with the bundled Zephyr firmware.
#
# Idempotent: if /var/lib/moab-hat-flashed exists and matches the SHA-256 of
# the bundled firmware, this exits 0 immediately. Otherwise it drives the HAT
# into its MCUboot bootloader, uploads the firmware over /dev/ttyAMA1 with
# mcumgr, and on success writes the marker so future boots are no-ops.
#
# Designed to be invoked by moab-hat-flash.service (systemd oneshot). On
# failure it exits non-zero so systemd's Restart=on-failure can retry.
#
# Protocol details adapted from microsoft/moabian/bin/flash (MIT) — see
# ../NOTICE for attribution.

set -euo pipefail

FW_DIR="${FW_DIR:-/opt/moab-balance/firmware}"
FW_BIN="${FW_DIR}/v3.bin"
FW_SHA="${FW_DIR}/v3.bin.sha256"
MARKER="${MARKER:-/var/lib/moab-hat-flashed}"
MCUMGR="${MCUMGR:-/usr/local/bin/mcumgr}"
UART="${UART:-/dev/ttyAMA1}"
BAUD="${BAUD:-115200}"

# GPIO BCM numbers (must match Microsoft's bootloader ABI).
PIN_HAT_EN=20
PIN_BOOT_EN=5
PIN_HAT_RESET=6

log() { printf '[flash-hat] %s\n' "$*"; }
die() { log "FATAL: $*" >&2; exit 1; }

[[ ${EUID} -eq 0 ]] || die "must run as root"

[[ -r "${FW_BIN}" ]] || die "firmware not found at ${FW_BIN}"
[[ -r "${FW_SHA}" ]] || die "firmware checksum not found at ${FW_SHA}"
command -v "${MCUMGR}" >/dev/null 2>&1 || die "mcumgr not found at ${MCUMGR}"
command -v raspi-gpio >/dev/null 2>&1 || die "raspi-gpio not installed"

EXPECTED_SHA="$(awk '{print $1}' "${FW_SHA}")"
ACTUAL_SHA="$(sha256sum "${FW_BIN}" | awk '{print $1}')"
[[ "${EXPECTED_SHA}" == "${ACTUAL_SHA}" ]] \
    || die "firmware integrity check failed (expected ${EXPECTED_SHA}, got ${ACTUAL_SHA})"

if [[ -f "${MARKER}" ]] && [[ "$(cat "${MARKER}" 2>/dev/null)" == "${EXPECTED_SHA}" ]]; then
    log "HAT already flashed with ${EXPECTED_SHA}, nothing to do."
    exit 0
fi

[[ -c "${UART}" ]] || die "UART ${UART} not present — is dtoverlay=uart1 enabled in /boot/firmware/config.txt?"

log "Putting HAT into bootloader mode..."
raspi-gpio set ${PIN_HAT_EN}    op
raspi-gpio set ${PIN_BOOT_EN}   op
raspi-gpio set ${PIN_HAT_RESET} op
raspi-gpio set ${PIN_HAT_EN}    dh
raspi-gpio set ${PIN_BOOT_EN}   dh
raspi-gpio set ${PIN_HAT_RESET} dh
sleep 1
raspi-gpio set ${PIN_HAT_RESET} dl

log "Uploading firmware ${FW_BIN} (${EXPECTED_SHA})..."
"${MCUMGR}" --conntype=serial --connstring="${UART},baud=${BAUD}" image upload "${FW_BIN}"

log "Resetting HAT into application mode..."
raspi-gpio set ${PIN_BOOT_EN}   dl
raspi-gpio set ${PIN_HAT_RESET} dh
sleep 1
raspi-gpio set ${PIN_HAT_RESET} dl

install -d -m 0755 "$(dirname "${MARKER}")"
printf '%s\n' "${EXPECTED_SHA}" > "${MARKER}"
log "Done. Marker written to ${MARKER}."
