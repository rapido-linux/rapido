#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2025, all rights reserved.

_vm_ar_env_check || exit 1

set -x

modprobe nvme
modprobe virtio_blk
modprobe zram num_devices="0" || _fatal "failed to load zram module"

_vm_ar_hosts_create
_vm_ar_dyn_debug_enable

_fstests_users_groups_provision

fstests_cfg="${FSTESTS_SRC}/configs/$(hostname -s).config"
cat > "$fstests_cfg" << EOF
MODULAR=0
TEST_DIR=/mnt/test
SCRATCH_MNT=/mnt/scratch
USE_KMEMLEAK=yes
FSTYP=xfs
MKFS_OPTIONS=
EOF
_fstests_devs_provision "$fstests_cfg"
. "$fstests_cfg"

mkdir -p "$TEST_DIR" "$SCRATCH_MNT"
mkfs."${FSTYP}" $MKFS_OPTIONS -f "$TEST_DEV" || _fatal "mkfs failed"
mount -t "$FSTYP" "$TEST_DEV" "$TEST_DIR" || _fatal

# xfstests does *not* do scratch mkfs+mount for -overlayfs backing
mkfs."${FSTYP}" $MKFS_OPTIONS -f "$SCRATCH_DEV" || _fatal "mkfs failed"

# fstests generic/131 needs loopback networking
ip link set dev lo up

set +x

echo "Ready for FSQA, e.g.: ./check -overlay"

cd "$FSTESTS_SRC" || _fatal
[[ -n "$FSTESTS_AUTORUN_CMD" ]] && eval "$FSTESTS_AUTORUN_CMD"
