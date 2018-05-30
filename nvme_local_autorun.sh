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

if [ ! -f /vm_autorun.env ]; then
	echo "Error: autorun scripts must be run from within an initramfs VM"
	exit 1
fi

. /vm_autorun.env

function _zram_hot_add() {
	[ -e /sys/class/zram-control/hot_add ] \
		|| _fatal "zram hot_add sysfs path missing (old kernel?)"

	local zram_size="$1"
	local zram_num=$(cat /sys/class/zram-control/hot_add) \
		|| _fatal "zram hot add failed"
	local zram_dev="/dev/zram${zram_num}"

	echo "$zram_size" > \
		/sys/devices/virtual/block/zram${zram_num}/disksize \
		|| _fatal "failed to set size for $zram_dev"
	echo "$zram_dev"
}

set -x

#### start udevd
ps -eo args | grep -v grep | grep /usr/lib/systemd/systemd-udevd \
	|| /usr/lib/systemd/systemd-udevd --daemon

modprobe configfs
cat /proc/mounts | grep configfs &> /dev/null
if [ $? -ne 0 ]; then
	mount -t configfs configfs /sys/kernel/config/
fi

modprobe nvme-core
modprobe nvme-fabrics
modprobe nvme-loop
modprobe nvmet
modprobe zram num_devices="0"

_vm_ar_dyn_debug_enable

export_blockdev=$(_zram_hot_add "1G")
[ -b "$export_blockdev" ] || _fatal "$export_blockdev device not available"

nvmet_cfs="/sys/kernel/config/nvmet/"
nvmet_subsystem="nvmf-test"
mkdir -p ${nvmet_cfs}/subsystems/${nvmet_subsystem} || _fatal
echo 1 > ${nvmet_cfs}/subsystems/${nvmet_subsystem}/attr_allow_any_host \
	|| _fatal
mkdir ${nvmet_cfs}/subsystems/${nvmet_subsystem}/namespaces/1 || _fatal
echo -n $export_blockdev \
	> ${nvmet_cfs}/subsystems/${nvmet_subsystem}/namespaces/1/device_path \
	|| _fatal
echo -n 1 \
	> ${nvmet_cfs}/subsystems/${nvmet_subsystem}/namespaces/1/enable \
	|| _fatal

mkdir ${nvmet_cfs}/ports/1 || _fatal
echo loop > ${nvmet_cfs}/ports/1/addr_trtype || _fatal

ln -s ${nvmet_cfs}/subsystems/${nvmet_subsystem} \
	${nvmet_cfs}/ports/1/subsystems/${nvmet_subsystem} || _fatal

echo "transport=loop,nqn=${nvmet_subsystem}" > /dev/nvme-fabrics || _fatal

set +x

echo "$export_blockdev mapped via NVMe loopback"
