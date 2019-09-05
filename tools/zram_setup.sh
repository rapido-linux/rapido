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
#
# provision and mount zram compressed ramdisks

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

ZRAM_INITRD_SIZE="1G"
ZRAM_INITRD_MNT="${RAPIDO_DIR}/initrds"

ZRAM_BACKUP_DIR=`mktemp --tmpdir -d zram_backup.XXXXXXXXXX` || _fail
trap "rm -f ${ZRAM_BACKUP_DIR}/readme.txt && rmdir $ZRAM_BACKUP_DIR" 0 1 2 3 15

set -x

function _zram_setup() {
	local zram_name=$1
	local zram_size=$2
	local zram_mnt=$3
	local zram_mnt_owner=$4
	local zram_dev="/dev/${zram_name}"

	if [ -d $zram_mnt ]; then
		mountpoint -q $zram_mnt && _fail "$zram_mnt already mounted"
	else
		mkdir -p $zram_mnt || _fail "$zram_mnt creation failed"
		chown $zram_mnt_owner $zram_mnt || _fail
	fi

	echo "${zram_size}" > /sys/block/$zram_name/disksize || _fail

	mkfs.xfs $zram_dev || _fail

	mount $zram_dev $zram_mnt || _fail
	chown $zram_mnt_owner $zram_mnt || _fail

	echo "mounted $zram_name for $zram_mnt_owner at $zram_mnt"
}

num_zram_devs=1
modprobe zram num_devices="${num_zram_devs}" || _fail
zram_i=0

# backup readme.txt before it's mounted over, so that git doesn't detect removal
cp -p ${ZRAM_INITRD_MNT}/readme.txt ${ZRAM_BACKUP_DIR}/
# use rapido dir ownership for initramfs subdir mount point
owner=`stat --format="%U:%G" $RAPIDO_DIR` || _fail
_zram_setup "zram${zram_i}" $ZRAM_INITRD_SIZE $ZRAM_INITRD_MNT $owner
cp -p ${ZRAM_BACKUP_DIR}/readme.txt ${ZRAM_INITRD_MNT}/
