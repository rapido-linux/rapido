#!/bin/bash
#
# Copyright (C) 2020 Western Digital Corporation, all rights reserved.
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

export PATH="${ZONEFSTOOLS_SRC}/src/:${PATH}"

# path to zonefs-tests within the initramfs
ZONEFSTESTS_DIR="/zonefs-tests"
[ -d "$ZONEFSTESTS_DIR" ] || _fatal "zonefs-tests missing"

modprobe null_blk nr_devices="0" || _fatal "failed to load zram module"

_vm_ar_dyn_debug_enable
_vm_ar_configfs_mount

# create the zonefs null_blk device.
dev="/sys/kernel/config/nullb/nullb0"
mkdir "$dev" || _fatal "cannot create nullb0 device"

echo 4096 > "$dev"/blocksize
echo 0 > "$dev"/completion_nsec
echo 0 > "$dev"/irqmode
echo 2 > "$dev"/queue_mode
echo 4096 > "$dev"/size
echo 1024 > "$dev"/hw_queue_depth
echo 1 > "$dev"/memory_backed
echo 1 > "$dev"/zoned
echo 128 > "$dev"/zone_size
echo 2 > "$dev"/zone_nr_conv
echo 1 > "$dev"/power

mkzonefs -f /dev/nullb0

set +x

echo "/dev/nullb0 provisioned and ready for zonefs-tests"

if [ -n "$ZONEFSTESTS_AUTORUN_CMD" ]; then
	cd ${ZONEFSTESTS_DIR} || _fatal
	eval "$ZONEFSTESTS_AUTORUN_CMD"
fi
