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
	local netd_flag netd_mach_id i vm_tap tap_mac n
	local vm_resources=()
	local vm_num_kparam="rapido.vm_num=${vm_num}"
	local qemu_netdev=()
	local kcmdline=(rd.systemd.unit=emergency.target \
		rd.shell=1 "console=$QEMU_KERNEL_CONSOLE" \
		$QEMU_EXTRA_KERNEL_PARAMS)

	[ -f "$DRACUT_OUT" ] \
	   || _fail "no initramfs image at ${DRACUT_OUT}. Run \"cut_X\" script?"

	# XXX could use systemd.hostname=, but it requires systemd-hostnamed
	n=$(head -n1 "${RAPIDO_DIR}/net-conf/vm${vm_num}/hostname" 2>/dev/null) \
		&& kcmdline+=("rapido.hostname=\"${n}\"")

	_rt_qemu_resources_get "${DRACUT_OUT}" vm_resources netd_flag \
		|| _fail "failed to get qemu resource parameters"

	if [[ -z $netd_flag ]]; then
		# this image doesn't require network access
		qemu_netdev+=(-net none) # override default (-net nic -net user)
	else
		# networkd needs a hex unique ID (for dhcp leases, etc.)
		# TODO could use value in .network config instead?
		netd_mach_id="$(echo $vm_num_kparam | md5sum)" \
			|| _fail "failed to generate networkd machine-id"

		kcmdline+=(net.ifnames=0 "systemd.machine_id=${netd_mach_id% *}")

		[ -d "${RAPIDO_DIR}/net-conf/vm${vm_num}" ] \
			|| _fail "net-conf/vm${vm_num} configuration missing"

		n=0
		for i in $(ls "${RAPIDO_DIR}/net-conf/vm${vm_num}"); do
			[[ $i =~ ^(.*)\.network$ ]] || continue
			vm_tap="${BASH_REMATCH[1]}"

			# calculate a vNIC MAC based on the VM#
			# and corresponding host tapdev name.
			tap_mac=$(echo "vm${vm_num}.${vm_tap}" | md5sum | sed \
			  's/^\(..\)\(..\)\(..\)\(..\)\(..\).*$/b8:\1:\2:\3:\4:\5/') \
			  || _fail "failed to generate vm${vm_num}.${vm_tap} MAC"

			# allow guest to [match] net-conf devices based on MAC.
			# XXX this could get too long for the kernel. The netd
			# [match] entry could instead be appended at cut time.
			kcmdline+=("rapido.mac.${vm_tap}=${tap_mac}")

			# each entry is expected to match a corresponding tapdev
			qemu_netdev+=(
			  "-device"
			  "virtio-net,netdev=if${n},mac=${tap_mac}"
			  "-netdev"
			  "tap,id=if${n},script=no,downscript=no,ifname=${vm_tap}"
			)
			((n++))
		done
	fi

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
		-append "$vm_num_kparam ${kcmdline[*]}" \
		-pidfile "$vm_pid_file" \
		"${qemu_netdev[@]}" \
		$QEMU_EXTRA_ARGS
	exit $?
}

# The VMs limit is arbitrary and with the new flexible net-conf we could remove
# it completely. It's up to the user to make sure that enough tap devices have
# been created to satisfy the net-conf/vm# configuration.
for ((i = 1; i <= 100; i++)); do
	[ -z "$(_vm_is_running $i)" ] && _vm_start $i
done
# _vm_start exits when done, so we only get here if none were started
_fail "Currently Rapido supports a maximum of 100 VMs"
