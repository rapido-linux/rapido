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

_vm_ar_env_check || exit 1

set -x

export PATH="${ZONEFSTOOLS_SRC}/src/:${PATH}"

# path to zonefs-tests within the initramfs
ZONEFSTESTS_DIR="/zonefs-tests"
[ -d "$ZONEFSTESTS_DIR" ] || _fatal "zonefs-tests missing"

modprobe scsi_debug zbc=host-managed zone_size_mb=64 virtual_gb=4 \
	sector_size=4096 zone_nr_conv=3

for dev_sysfs in /sys/block/*; do
	if [ ! -f $dev_sysfs/device/model ]; then
		continue
	fi


	model=$(cat $dev_sysfs/device/model)

	if [ x$model == "xscsi_debug" ]; then
		dev=${dev_sysfs/\/sys\/block\//}
		break
	fi

done

_vm_ar_dyn_debug_enable

# create the zonefs null_blk device.

mkzonefs -f /dev/$dev

set +x

echo "/dev/$dev provisioned and ready for zonefs-tests"

if [ -n "$ZONEFSTESTS_AUTORUN_CMD" ]; then
	cd ${ZONEFSTESTS_DIR} || _fatal
	eval "$ZONEFSTESTS_AUTORUN_CMD"
fi
