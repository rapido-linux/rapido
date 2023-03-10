#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2023, all rights reserved.

_vm_ar_env_check || exit 1

set -x

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
UDF_MKFS_OPTIONS="--utf8 --blocksize=4096 --media-type=hd"
USE_KMEMLEAK=yes
FSTYP=udf
EOF
[ -f "${FSTESTS_SRC}/src/udf_test" ] \
	|| echo "DISABLE_UDF_TEST=1" >> "$fstests_cfg"
_fstests_devs_provision "$fstests_cfg"
. "$fstests_cfg"

mkdir -p "$TEST_DIR" "$SCRATCH_MNT"
mkudffs $UDF_MKFS_OPTIONS "$TEST_DEV" || _fatal "mkfs failed"
mount -t "$FSTYP" "$TEST_DEV" "$TEST_DIR" || _fatal
# xfstests can handle scratch mkfs+mount

# fstests generic/131 needs loopback networking
ip link set dev lo up

set +x

echo "$FSTYP filesystem ready for FSQA"

cd "$FSTESTS_SRC" || _fatal
if [ -n "$FSTESTS_AUTORUN_CMD" ]; then
	eval "$FSTESTS_AUTORUN_CMD"
fi
