#!/bin/bash -e
# Host-side script: copies the pre-staged source tree, the cross-compiled
# mcumgr binary, and the systemd units into the chroot. The actual heavy
# lifting (apt, venv, systemctl enable, config.txt edits) happens in the
# next sub-stage's *-run-chroot.sh.
#
# pi-gen invokes us via `bash -e` (a subshell) and pushd's into the sub-stage
# directory first, so SUB_STAGE_DIR is *not* in our env — but the working
# directory IS the sub-stage dir. Use relative paths, like every stock
# pi-gen *-run.sh does.

# files/ is laid out exactly like the destination paths inside the rootfs.
# A simple cp -a preserves ownership/perms and is the standard pi-gen pattern.
cp -a files/. "${ROOTFS_DIR}/"

# Make sure the ones that need to be executable are.
chmod 0755 "${ROOTFS_DIR}/usr/local/bin/mcumgr"
chmod 0755 "${ROOTFS_DIR}/opt/moab-balance/firmware/flash-hat.sh"
chmod 0755 "${ROOTFS_DIR}/opt/moab-balance/install.sh"
