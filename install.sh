#!/usr/bin/env bash
# Install moab-balance on a Raspberry Pi running the stock Moabian image.
#
# This script:
#   1. Disables the stock Moab service (so it never fights us for the HAT).
#   2. Copies the moab_balance package and systemd unit into /opt and /etc.
#   3. Creates a Python virtualenv with the (small) runtime dependencies.
#   4. Enables and starts the new moab-balance.service.
#
# Re-running it is safe: the venv is reused if already present.

set -euo pipefail

INSTALL_DIR="/opt/moab-balance"
SERVICE_NAME="moab-balance.service"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${EUID}" -ne 0 ]]; then
    exec sudo --preserve-env=PATH "$0" "$@"
fi

echo "==> Stopping and disabling the stock Moab service (if present)"
systemctl stop moab.service 2>/dev/null || true
systemctl disable moab.service 2>/dev/null || true

echo "==> Installing system packages"
apt-get update
# python3-opencv pulls in libatlas, libavcodec, etc. — much faster and lighter
# on a Pi than `pip install opencv-python`.
apt-get install -y --no-install-recommends \
    python3 python3-venv python3-pip python3-numpy python3-opencv \
    python3-rpi.gpio python3-spidev

echo "==> Copying source to ${INSTALL_DIR}"
install -d -m 0755 "${INSTALL_DIR}"
rm -rf "${INSTALL_DIR}/moab_balance"
cp -r "${SCRIPT_DIR}/moab_balance" "${INSTALL_DIR}/"
cp    "${SCRIPT_DIR}/pyproject.toml" "${INSTALL_DIR}/"
cp    "${SCRIPT_DIR}/LICENSE"        "${INSTALL_DIR}/"
cp    "${SCRIPT_DIR}/NOTICE"         "${INSTALL_DIR}/"

echo "==> Creating Python virtualenv (with system site-packages so we reuse apt opencv)"
if [[ ! -d "${INSTALL_DIR}/venv" ]]; then
    python3 -m venv --system-site-packages "${INSTALL_DIR}/venv"
fi
"${INSTALL_DIR}/venv/bin/pip" install --upgrade pip >/dev/null
"${INSTALL_DIR}/venv/bin/pip" install -e "${INSTALL_DIR}" >/dev/null

chown -R pi:pi "${INSTALL_DIR}"

echo "==> Installing systemd unit"
install -m 0644 "${SCRIPT_DIR}/systemd/${SERVICE_NAME}" "/etc/systemd/system/${SERVICE_NAME}"
systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"
systemctl restart "${SERVICE_NAME}"

echo
echo "Done. Status:"
systemctl --no-pager --full status "${SERVICE_NAME}" || true
echo
echo "Tail logs with:    journalctl -u ${SERVICE_NAME} -f"
echo "Stop with:         sudo systemctl stop ${SERVICE_NAME}"
echo "Restore stock SW:  sudo systemctl disable --now ${SERVICE_NAME} && sudo systemctl enable --now moab.service"
