#!/bin/bash -e
# Chroot-side script: configures Pi hardware, creates the moab-balance venv,
# and enables the systemd services so the Pi balances on first boot.

INSTALL_DIR="/opt/moab-balance"
BOOT_CONFIG="/boot/firmware/config.txt"

on_chroot << EOF
set -e

# ---- enable SPI (HAT) and UART1 (HAT MCU bootloader) -------------------
# Don't touch [cm4]/[cm5] sections; append our settings under [all] (which
# pi-gen's stock config.txt ends with).
if ! grep -qE '^[[:space:]]*dtparam=spi=on' "${BOOT_CONFIG}"; then
    echo '' >> "${BOOT_CONFIG}"
    echo '# moab-balance: SPI for HAT runtime, uart1 for HAT bootloader (mcumgr)' >> "${BOOT_CONFIG}"
    echo 'dtparam=spi=on' >> "${BOOT_CONFIG}"
fi
if ! grep -qE '^[[:space:]]*dtoverlay=uart1' "${BOOT_CONFIG}"; then
    echo 'dtoverlay=uart1' >> "${BOOT_CONFIG}"
fi
# camera_auto_detect=1 is already on by default in stock pi-gen; don't touch.

# ---- python venv (reusing apt's opencv) --------------------------------
python3 -m venv --system-site-packages ${INSTALL_DIR}/venv
${INSTALL_DIR}/venv/bin/pip install --upgrade pip >/dev/null
${INSTALL_DIR}/venv/bin/pip install -e ${INSTALL_DIR} >/dev/null

# ---- ownership ---------------------------------------------------------
chown -R ${FIRST_USER_NAME}:${FIRST_USER_NAME} ${INSTALL_DIR}

# ---- enable services (start on next boot) ------------------------------
systemctl daemon-reload
systemctl enable moab-hat-flash.service
systemctl enable moab-balance.service
EOF
