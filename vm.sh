#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2016-2022, all rights reserved.

RAPIDO_DIR="`dirname $0`"
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_qemu_args

_vm_is_running() {
	local vm_num=$1
	local vm_pid_file="${RAPIDO_DIR}/initrds/rapido_vm${vm_num}.pid"

	[ -f $vm_pid_file ] || return

	ps -p "$(head -n1 $vm_pid_file)" > /dev/null && echo "1"
}

_vm_start() {
	local vm_num=$1
	local vm_pid_file="${RAPIDO_DIR}/initrds/rapido_vm${vm_num}.pid"
	local netd_flag
	local vm_resources=()

	[ -f "$DRACUT_OUT" ] \
	   || _fail "no initramfs image at ${DRACUT_OUT}. Run \"cut_X\" script?"

	if [ -z "$vm_num" ] || [ $vm_num -lt 1 ] || [ $vm_num -gt 2 ]; then
		_fail "a maximum of two network connected VMs are supported"
	fi

	_rt_qemu_resources_get "${DRACUT_OUT}" vm_resources netd_flag \
		|| _fail "failed to get qemu resource parameters"

	# XXX rapido.conf VM parameters are pretty inconsistent and confusing
	# moving to a VM${vm_num}_MAC_ADDR or ini style config would make sense
	local qemu_netdev=""
	if [[ -z $netd_flag ]]; then
		# this image doesn't require network access
		qemu_netdev="-net none"	# override default (-net nic -net user)
	else
		eval local mac_addr='$MAC_ADDR'${vm_num}
		[ -n "$mac_addr" ] \
			|| _fail "MAC_ADDR${vm_num} not configured"
		eval local tap='$TAP_DEV'$((vm_num - 1))
		[ -n "$tap" ] \
			|| _fail "TAP_DEV$((vm_num - 1)) not configured"
		qemu_netdev="-device virtio-net,netdev=nw1,mac=${mac_addr} \
			-netdev tap,id=nw1,script=no,downscript=no,ifname=${tap}"
	fi

	local qemu_more_args="$qemu_netdev $QEMU_EXTRA_ARGS"

	# rapido.conf might have specified a shared folder for qemu
	if [ -n "$VIRTFS_SHARE_PATH" ]; then
		vm_resources+=(-virtfs
			"local,path=${VIRTFS_SHARE_PATH},mount_tag=host0,security_model=mapped,id=host0")
	fi

	$QEMU_BIN \
		$QEMU_ARCH_VARS \
		"${vm_resources[@]}" \
		-kernel "$QEMU_KERNEL_IMG" \
		-initrd "$DRACUT_OUT" \
		-append "rapido.vm_num=${vm_num} net.ifnames=0 \
			 rd.systemd.unit=emergency.target \
		         rd.shell=1 console=$QEMU_KERNEL_CONSOLE rd.lvm=0 rd.luks=0 \
			 $QEMU_EXTRA_KERNEL_PARAMS" \
		-pidfile "$vm_pid_file" \
		$qemu_more_args
	exit $?
}

[ -z "$(_vm_is_running 1)" ] && _vm_start 1
[ -z "$(_vm_is_running 2)" ] && _vm_start 2
# _vm_start exits when done, so we only get here if none were started
_fail "Currently Rapido only supports a maximum of two VMs"
