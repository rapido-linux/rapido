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

[ -f "$DRACUT_OUT" ] \
	|| _fail "no initramfs image at ${DRACUT_OUT}. Run \"cut_X\" script?"

kernel_img="${KERNEL_SRC}/arch/x86/boot/bzImage"
[ -f "$kernel_img" ] \
	|| _fail "no kernel image present at ${kernel_img}. Build needed?"

[ -n "$MAC_ADDR1" ] || _fail "MAC_ADDR1 not configured in rapido.conf"
[ -n "$MAC_ADDR2" ] || _fail "MAC_ADDR2 not configured in rapido.conf"

set -x

# cut_ script may have specified some parameters for qemu (9p share)
qemu_cut_args="$(getfattr --only-values -n $QEMU_ARGS_XATTR $DRACUT_OUT \
							2> /dev/null)"
qemu_more_args="$QEMU_EXTRA_ARGS $qemu_cut_args"

if [ "$IP_ADDR1_DHCP" = "1" ]; then
	kern_ip_addr1="dhcp"
else
	[ -n "$IP_ADDR1" ] || _fail "IP_ADDR1 not configured in rapido.conf"
	kern_ip_addr1="${IP_ADDR1}:::255.255.255.0:${HOSTNAME1}"
fi

pgrep -a qemu-system | grep -q mac=${MAC_ADDR1} && vm1_running=1
if [ -z "$vm1_running" ]; then
	qemu-kvm -smp cpus=2 -m 512 \
		 -kernel "$kernel_img" \
		 -initrd "$DRACUT_OUT" \
		 -device e1000,netdev=nw1,mac=${MAC_ADDR1} \
		 -netdev tap,id=nw1,script=no,downscript=no,ifname=${TAP_DEV0} \
		 -append "ip=${kern_ip_addr1} rd.systemd.unit=emergency \
			  rd.shell=1 console=ttyS0 rd.lvm=0 rd.luks=0" \
		 $qemu_more_args
	exit $?
fi

if [ "$IP_ADDR2_DHCP" = "1" ]; then
	kern_ip_addr2="dhcp"
else
	[ -n "$IP_ADDR2" ] || _fail "IP_ADDR2 not configured in rapido.conf"
	kern_ip_addr2="${IP_ADDR2}:::255.255.255.0:${HOSTNAME2}"
fi

pgrep -a qemu-system | grep -q mac=${MAC_ADDR2} && vm2_running=1
if [ -z "$vm2_running" ]; then
	qemu-kvm -smp cpus=2 -m 512 \
		 -kernel "$kernel_img" \
		 -initrd "$DRACUT_OUT" \
		 -device e1000,netdev=nw1,mac=${MAC_ADDR2} \
		 -netdev tap,id=nw1,script=no,downscript=no,ifname=${TAP_DEV1} \
		 -append "ip=${kern_ip_addr2} rd.systemd.unit=emergency \
			  rd.shell=1 console=ttyS0 rd.lvm=0 rd.luks=0" \
		 $qemu_more_args
	exit $?
fi
