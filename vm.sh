#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2016-2018, all rights reserved.
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

_rt_require_qemu_kvm_bin

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
	local kernel_img="${KERNEL_SRC}/arch/x86/boot/bzImage"

	[ -f "$DRACUT_OUT" ] \
	   || _fail "no initramfs image at ${DRACUT_OUT}. Run \"cut_X\" script?"

	if [ -z "$vm_num" ] || [ $vm_num -lt 1 ]; then
		_fail "invalid vm_num: $vm_num"
	fi

	# XXX rapido.conf VM parameters are pretty inconsistent and confusing
	# moving to a VM${vm_num}_MAC_ADDR or ini style config would make sense
	local qemu_netdev=""
	local kern_ip_addr=""
	if [ -n "$(_rt_xattr_vm_networkless_get ${DRACUT_OUT})" ]; then
		# this image doesn't require network access
		kern_ip_addr="none"
		qemu_netdev="-net none"	# override default (-net nic -net user)
	else
		eval local mac_addr='$MAC_ADDR'${vm_num}
		[ -n "$mac_addr" ] \
			|| _fail "MAC_ADDR${vm_num} not configured"
		eval local tap='$TAP_DEV'$((vm_num - 1))
		[ -n "$tap" ] \
			|| _fail "TAP_DEV$((vm_num - 1)) not configured"
		eval local is_dhcp='$IP_ADDR'${vm_num}'_DHCP'
		if [ "$is_dhcp" = "1" ]; then
			kern_ip_addr="dhcp"
		else
			eval local hostname='$HOSTNAME'${vm_num}
			[ -n "$hostname" ] \
				|| _fail "HOSTNAME${vm_num} not configured"
			eval local ip_addr='$IP_ADDR'${vm_num}
			[ -n "$ip_addr" ] \
				|| _fail "IP_ADDR${vm_num} not configured"
			kern_ip_addr="${ip_addr}:::255.255.255.0:${hostname}"
		fi
		qemu_netdev="-device e1000,netdev=nw1,mac=${mac_addr} \
			-netdev tap,id=nw1,script=no,downscript=no,ifname=${tap}"
	fi

	# cut_ script may have specified some parameters for qemu (9p share)
	local qemu_cut_args="$(_rt_xattr_qemu_args_get ${DRACUT_OUT})"
	local qemu_more_args="$qemu_netdev $QEMU_EXTRA_ARGS $qemu_cut_args"

	local vm_resources="$(_rt_xattr_vm_resources_get ${DRACUT_OUT})"
	[ -n "$vm_resources" ] || vm_resources="-smp cpus=2 -m 512"

	[ -f "$kernel_img" ] \
	   || _fail "no kernel image present at ${kernel_img}. Build needed?"

	$QEMU_KVM_BIN \
		$vm_resources \
		-kernel "$kernel_img" \
		-initrd "$DRACUT_OUT" \
		-append "ip=${kern_ip_addr} rd.systemd.unit=emergency \
		         rd.shell=1 console=ttyS0 rd.lvm=0 rd.luks=0" \
		-pidfile "$vm_pid_file" \
		$qemu_more_args
	exit $?
}

set -x

for i in `seq 1 "$VM_MAX_COUNT"`; do
	[ -z "$(_vm_is_running ${i})" ] && _vm_start "$i"
done
# _vm_start exits when done, so we only get here if none were started
_fail "Currently Rapido only supports a maximum of $VM_MAX_COUNT VMs"
