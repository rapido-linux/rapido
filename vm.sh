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

RAPIDO_DIR="`dirname $0`"
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_qemu_args

function _vm_is_running
{
	local vm_num=$1
	local vm_pid_file="${RAPIDO_DIR}/initrds/rapido_vm${vm_num}.pid"

	[ -f $vm_pid_file ] || return

	ps -p "$(head -n1 $vm_pid_file)" > /dev/null && echo "1"
}

function _vm_start
{
	local vm_num=$1
	local vm_pid_file="${RAPIDO_DIR}/initrds/rapido_vm${vm_num}.pid"

	[ -f "$DRACUT_OUT" ] \
	   || _fail "no initramfs image at ${DRACUT_OUT}. Run \"cut_X\" script?"

	if [ -z "$vm_num" ] || [ $vm_num -lt 1 ] || [ $vm_num -gt 2 ]; then
		_fail "a maximum of two network connected VMs are supported"
	fi

	local qemu_netdev=""
	local kern_ip_addr=""
	if [ -n "$(_rt_xattr_vm_networkless_get ${DRACUT_OUT})" ]; then
		# this image doesn't require network access
		kern_ip_addr="none"
		qemu_netdev="-net none"	# override default (-net nic -net user)
	else
		eval local mac_addr='$VM'${vm_num}'_MAC_ADDR1'
		eval local tap='$TAP_DEV'$((vm_num - 1))
		[ -n "$tap" ] \
			|| _fail "TAP_DEV$((vm_num - 1)) not configured"
		eval local is_dhcp='$VM'${vm_num}'_IP_ADDR1_DHCP'
		if [ "$is_dhcp" = "1" ]; then
			kern_ip_addr="dhcp"
		else
			eval local hostname='$HOSTNAME'${vm_num}
			[ -n "$hostname" ] \
				|| _fail "HOSTNAME${vm_num} not configured"
			eval local ip_addr='$VM'${vm_num}'_IP_ADDR1'
			[ -n "$ip_addr" ] \
				|| _fail "VM${vm_num}_IP_ADDR1 not configured"
			kern_ip_addr="${ip_addr}:::255.255.255.0:${hostname}"
		fi
		qemu_netdev="-device virtio-net,netdev=nw1,mac=${mac_addr} \
			-netdev tap,id=nw1,script=no,downscript=no,ifname=${tap}"
	fi

	# cut_ script may have specified some parameters for qemu
	local qemu_cut_args="$(_rt_xattr_qemu_args_get ${DRACUT_OUT})"
	local qemu_more_args="$qemu_netdev $QEMU_EXTRA_ARGS $qemu_cut_args"

	local vm_resources="$(_rt_xattr_vm_resources_get ${DRACUT_OUT})"
	[ -n "$vm_resources" ] || vm_resources="-smp cpus=2 -m 512"

	# rapido.conf might have specified a shared folder for qemu
	local virtfs_share=""
	if [ -n "$VIRTFS_SHARE_PATH" ]; then
		virtfs_share="-virtfs \
		local,path=${VIRTFS_SHARE_PATH},mount_tag=host0,security_model=mapped,id=host0"
	fi

	$QEMU_BIN \
		$QEMU_ARCH_VARS \
		$vm_resources \
		-kernel "$QEMU_KERNEL_IMG" \
		-initrd "$DRACUT_OUT" \
		-append "rapido.vm_num=${vm_num} ip=${kern_ip_addr} \
			 rd.systemd.unit=emergency.target \
		         rd.shell=1 console=$QEMU_KERNEL_CONSOLE rd.lvm=0 rd.luks=0 \
			 $QEMU_EXTRA_KERNEL_PARAMS" \
		-pidfile "$vm_pid_file" \
		$virtfs_share \
		$qemu_more_args
	exit $?
}

[ -z "$(_vm_is_running 1)" ] && _vm_start 1
[ -z "$(_vm_is_running 2)" ] && _vm_start 2
# _vm_start exits when done, so we only get here if none were started
_fail "Currently Rapido only supports a maximum of two VMs"
