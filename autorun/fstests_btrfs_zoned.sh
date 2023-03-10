#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) Western Digital Corporation 2021, all rights reserved.

create_zoned_null_blk()
{
	local dev="/sys/kernel/config/nullb/$1"
	mkdir "$dev" || _fatal "cannot create nullb0 device"

	local size=12800 # MB
	echo 2 > "$dev"/submit_queues
	echo "${size}" > "${dev}"/size
	echo 1 > "${dev}"/zoned
	echo 4 > "${dev}"/zone_nr_conv
	echo 1 > "${dev}"/memory_backed
	echo 1 > "$dev"/power
}

_vm_ar_env_check || exit 1

set -x

[ -n "$BTRFS_PROGS_SRC" ] && export PATH="${PATH}:${BTRFS_PROGS_SRC}"

_vm_ar_hosts_create

filesystem="btrfs"

modprobe null_blk nr_devices="0" || _fatal "failed to load null_blk module"

_vm_ar_dyn_debug_enable
_vm_ar_configfs_mount

_fstests_users_groups_provision

# create the btrfs null_blk devices.
for d in nullb0 nullb1; do
	create_zoned_null_blk $d
done

mkdir -p /mnt/test
mkdir -p /mnt/scratch

mkfs.${filesystem} -m single -d single /dev/nullb0 || _fatal "mkfs failed"
mount -t $filesystem /dev/nullb0 /mnt/test || _fatal
# xfstests can handle scratch mkfs+mount

[ -n "${FSTESTS_SRC}" ] || _fatal "FSTESTS_SRC unset"
[ -d "${FSTESTS_SRC}" ] || _fatal "$FSTESTS_SRC missing"

cfg="${FSTESTS_SRC}/configs/$(hostname -s).config"
cat > $cfg << EOF
FSTYP=btrfs
MODULAR=0
TEST_DIR=/mnt/test
TEST_DEV=/dev/nullb0
SCRATCH_MNT=/mnt/scratch
SCRATCH_DEV="/dev/nullb1"
USE_KMEMLEAK=yes
MIN_FSSIZE=$((5 * 256 * 1024 * 1024))
MKFS_OPTIONS="-d single -m single"
EOF

# fstests generic/131 needs loopback networking
ip link set dev lo up

set +x

echo "$filesystem filesystem ready for FSQA"

cd "$FSTESTS_SRC" || _fatal
if [ -n "$FSTESTS_AUTORUN_CMD" ]; then
	eval "$FSTESTS_AUTORUN_CMD"
fi
