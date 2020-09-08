#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2017, all rights reserved.
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

_vm_ar_env_check || exit 1

set -x

# path to blktests within the initramfs
BLKTESTS_DIR="/blktests"
[ -d "$BLKTESTS_DIR" ] || _fatal "blktests missing"

modprobe zram num_devices="1" || _fatal "failed to load zram module"

_vm_ar_dyn_debug_enable
_vm_ar_configfs_mount

echo "1G" > /sys/block/zram0/disksize || _fatal "failed to set zram disksize"

echo "TEST_DEVS=(/dev/zram0)" > ${BLKTESTS_DIR}/config

set +x

echo "/dev/zram0 provisioned and ready for ${BLKTESTS_DIR}/check"

if [ -n "$BLKTESTS_AUTORUN_CMD" ]; then
	cd ${BLKTESTS_DIR} || _fatal
	eval "$BLKTESTS_AUTORUN_CMD"
fi
