#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2018, all rights reserved.
#
# This library is free software; you can redistribute it and/or modify it
# under the terms of the GNU Lesser General Public License as published
# by the Free Software Foundation; either version 2.1 of the License, or
# (at your option) version 3.
#
# This library is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
# License for more details.

if [ ! -f /vm_autorun.env ]; then
	echo "Error: autorun scripts must be run from within an initramfs VM"
	exit 1
fi

. /vm_autorun.env

set -x

[ -n "$BTRFS_PROGS_SRC" ] && export PATH="${PATH}:${BTRFS_PROGS_SRC}"

hostname_fqn="`cat /proc/sys/kernel/hostname`" || _fatal "hostname unavailable"
hostname_short="${hostname_fqn%%.*}"
filesystem="btrfs"

# need hosts file for hostname -s
cat > /etc/hosts <<EOF
127.0.0.1	$hostname_fqn	$hostname_short
EOF

# use a 4-dev scratch pool for btrfs
num_devs="5"
modprobe zram num_devices="${num_devs}" || _fatal "failed to load zram module"

_vm_ar_dyn_debug_enable

for i in $(seq 0 $((num_devs - 1))); do
	echo "1G" > /sys/block/zram${i}/disksize \
		|| _fatal "failed to set zram disksize"
done

mkdir -p /mnt/test
mkdir -p /mnt/scratch

mkfs.${filesystem} /dev/zram0 || _fatal "mkfs failed"
mount -t $filesystem /dev/zram0 /mnt/test || _fatal
# xfstests can handle scratch mkfs+mount

[ -n "${FSTESTS_SRC}" ] || _fatal "FSTESTS_SRC unset"
[ -d "${FSTESTS_SRC}" ] || _fatal "$FSTESTS_SRC missing"

cfg="${FSTESTS_SRC}/configs/$(hostname -s).config"
cat > $cfg << EOF
MODULAR=0
TEST_DIR=/mnt/test
TEST_DEV=/dev/zram0
SCRATCH_MNT=/mnt/scratch
SCRATCH_DEV_POOL="/dev/zram1 /dev/zram2 /dev/zram3 /dev/zram4"
EOF

mkdir -p home/fsgqa
groupadd fsgqa
useradd -g fsgqa fsgqa

set +x

echo "$filesystem filesystem ready for FSQA"

if [ -n "$FSTESTS_AUTORUN_CMD" ]; then
	cd ${FSTESTS_SRC} || _fatal
	eval "$FSTESTS_AUTORUN_CMD"
fi
