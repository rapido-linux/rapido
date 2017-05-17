#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2016, all rights reserved.
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

# path to xfstests within the initramfs
XFSTESTS_DIR="/fstests/xfstests"

hostname_fqn="`cat /proc/sys/kernel/hostname`" || _fatal "hostname unavailable"
hostname_short="${hostname_fqn%%.*}"
filesystem="btrfs"

# need hosts file for hostname -s
cat > /etc/hosts <<EOF
127.0.0.1	$hostname_fqn	$hostname_short
EOF


# enable debugfs
cat /proc/mounts | grep debugfs &> /dev/null
if [ $? -ne 0 ]; then
	mount -t debugfs debugfs /sys/kernel/debug/
fi

cat /proc/mounts | grep configfs &> /dev/null
if [ $? -ne 0 ]; then
	mount -t configfs configfs /sys/kernel/config/
fi

modprobe zram num_devices="2" || _fatal "failed to load zram module"

echo "1G" > /sys/block/zram0/disksize || _fatal "failed to set zram disksize"
echo "1G" > /sys/block/zram1/disksize || _fatal "failed to set zram disksize"

mkfs.${filesystem} /dev/zram0 || _fatal "mkfs failed"
mkfs.${filesystem} /dev/zram1 || _fatal "mkfs failed"

for i in $DYN_DEBUG_MODULES; do
	echo "module $i +pf" > /sys/kernel/debug/dynamic_debug/control || _fatal
done
for i in $DYN_DEBUG_FILES; do
	echo "file $i +pf" > /sys/kernel/debug/dynamic_debug/control || _fatal
done

mkdir -p /mnt/test
mkdir -p /mnt/scratch

mount -t $filesystem /dev/zram0 /mnt/test || _fatal
mount -t $filesystem /dev/zram1 /mnt/scratch || _fatal

if [ -d ${XFSTESTS_DIR} ]; then
	cat > ${XFSTESTS_DIR}/configs/`hostname -s`.config << EOF
MODULAR=0
TEST_DIR=/mnt/test
TEST_DEV=/dev/zram0
SCRATCH_MNT=/mnt/scratch
SCRATCH_DEV=/dev/zram1
EOF
fi

set +x

echo "$filesystem filesystem mounted at /mnt/test and /mnt/scratch"

if [ -n "$FSTESTS_AUTORUN_CMD" ]; then
	cd ${XFSTESTS_DIR} || _fatal
	eval "$FSTESTS_AUTORUN_CMD"
fi
