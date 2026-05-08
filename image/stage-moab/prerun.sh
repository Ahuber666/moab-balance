#!/bin/bash -e
# Standard pi-gen pattern: only copy from the previous stage if we don't
# already have a working tree (lets you re-run a single sub-stage cheaply).
if [ ! -d "${ROOTFS_DIR}" ]; then
    copy_previous
fi
