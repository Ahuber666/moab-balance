#!/bin/bash -e
# This whole file is fed to pi-gen's on_chroot as stdin (see run_sub_stage in
# pi-gen/scripts/common: `on_chroot < ${i}-run-chroot.sh`), so the body below
# is the bash that runs *inside* the qemu/native chroot of the rootfs being
# built. Do NOT wrap it in another `on_chroot << EOF` — that triggers a
# nested chroot from within the chroot and explodes with confusing realpath
# errors against /pi-gen/work/... paths that don't exist inside the rootfs.

INSTALL_DIR="/opt/moab-balance"
BOOT_CONFIG="/boot/firmware/config.txt"

# ---- enable SPI (HAT) and UART1 (HAT MCU bootloader) -----------------------
# Don't touch [cm4]/[cm5] sections; append our settings at the end (under the
# stock [all] section that pi-gen's config.txt ends with).
if ! grep -qE '^[[:space:]]*dtparam=spi=on' "${BOOT_CONFIG}"; then
    {
        echo ''
        echo '# moab-balance: SPI for HAT runtime, uart1 for HAT bootloader (mcumgr)'
        echo 'dtparam=spi=on'
    } >> "${BOOT_CONFIG}"
fi
if ! grep -qE '^[[:space:]]*dtoverlay=uart1' "${BOOT_CONFIG}"; then
    echo 'dtoverlay=uart1' >> "${BOOT_CONFIG}"
fi

# ---- python venv (reusing apt's opencv) ------------------------------------
python3 -m venv --system-site-packages "${INSTALL_DIR}/venv"
"${INSTALL_DIR}/venv/bin/pip" install --upgrade pip >/dev/null
"${INSTALL_DIR}/venv/bin/pip" install -e "${INSTALL_DIR}" >/dev/null

# ---- ownership -------------------------------------------------------------
# FIRST_USER_NAME is exported by pi-gen's build.sh into the chroot env.
chown -R "${FIRST_USER_NAME}:${FIRST_USER_NAME}" "${INSTALL_DIR}"

# ---- enable services (start on next boot) ----------------------------------
systemctl daemon-reload
systemctl enable moab-hat-flash.service
systemctl enable moab-balance.service
