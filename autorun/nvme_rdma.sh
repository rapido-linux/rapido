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
_vm_ar_configfs_mount

#ip link set eth0 mtu 9000
#sleep 5 # give the network stack some time

modprobe ib_core
modprobe ib_uverbs
modprobe rdma_ucm
modprobe rdma-rxe
modprobe nvme-core
modprobe nvme-fabrics
modprobe nvme-rdma
modprobe nvmet
modprobe zram num_devices="0"

_vm_ar_dyn_debug_enable

rdma link add rxe0 type rxe netdev eth0 || _fatal

nvmet_cfs="/sys/kernel/config/nvmet/"
nvmet_subsystem="nvmf-test"

cfg_ips=()
_vm_ar_cfg_ips "1" cfg_ips
(( ${#cfg_ips[@]} > 0 )) || _fatal "vm1 lacks IP address config"
vm1_ip=${cfg_ips[0]}

# When run via vm1, act as a target.
# TODO split this into nvme_rdma_target / nvme_rdma_client, as this would be
# simpler and allow for testing against third party targets.
if (( $kcli_rapido_vm_num == 1 )); then
	export_blockdev=$(_zram_hot_add "1G")
	[ -b "$export_blockdev" ] || _fatal "$export_blockdev device not available"

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

	echo rdma > ${nvmet_cfs}/ports/1/addr_trtype || _fatal
	echo "$vm1_ip" > ${nvmet_cfs}/ports/1/addr_traddr || _fatal
	echo ipv4 > ${nvmet_cfs}/ports/1/addr_adrfam || _fatal
	echo 4420 > ${nvmet_cfs}/ports/1/addr_trsvcid || _fatal
	ln -s ${nvmet_cfs}/subsystems/${nvmet_subsystem} \
		${nvmet_cfs}/ports/1/subsystems/${nvmet_subsystem} || _fatal

	set +x
	echo "$export_blockdev mapped via NVMe over Fabrics RDMA on $vm1_ip"
fi

# When run via vm2, act as a client for the vm1 target.
if (( $kcli_rapido_vm_num == 2 )); then
	nvme connect -t rdma -a "$vm1_ip" -s 4420 -n nvmf-test || _fatal
	udevadm settle
	nvmedev=$(ls /dev/ | grep -Eo /dev/nvme[0-9]n[0-0])
	set +x
	echo "Remote NVMe over RDMA $vm1_ip mapped to $nvmedev"
fi
