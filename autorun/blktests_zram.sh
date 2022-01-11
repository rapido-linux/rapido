#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2017, all rights reserved.

_vm_ar_env_check || exit 1

set -x

modprobe zram num_devices="1" || _fatal "failed to load zram module"

_vm_ar_dyn_debug_enable
_vm_ar_configfs_mount

echo "1G" > /sys/block/zram0/disksize || _fatal "failed to set zram disksize"

echo "TEST_DEVS=(/dev/zram0)" > ${BLKTESTS_SRC}/config

set +x

echo "/dev/zram0 provisioned and ready for ${BLKTESTS_SRC}/check"

cd "$BLKTESTS_SRC" || _fatal
if [ -n "$BLKTESTS_AUTORUN_CMD" ]; then
	eval "$BLKTESTS_AUTORUN_CMD"
fi
