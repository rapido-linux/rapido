#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2022, all rights reserved.

_vm_ar_env_check || exit 1

set -x

# ublk uses O_DIRECT, so we can't just use a tmpfs backed file
modprobe zram num_devices="1" || _fatal "failed to load zram module"
modprobe ublk_drv || _fatal "failed to load ublk_drv kernel module"
_vm_ar_dyn_debug_enable
_ublksrv_env_init

echo "2G" > /sys/block/zram0/disksize || _fatal "failed to set zram disksize"
mkfs.xfs /dev/zram0 || _fatal
mkdir /mnt
mount /dev/zram0 /mnt || _fatal

truncate -s 1G /mnt/ublk.img
ublk add -t loop -f /mnt/ublk.img || _fatal "failed to add ublk device"
ublk list

set +x
