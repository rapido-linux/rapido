#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2017-2018, all rights reserved.
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

RAPIDO_DIR="`dirname $0`/.."
. "${RAPIDO_DIR}/runtime.vars"

set -x

if [ -n "$BR_DHCP_SRV_RANGE" ]; then
	dnsmasq_pid=`ps -eo pid,args | grep -v grep | grep dnsmasq \
			| grep -- --interface=$BR_DEV \
			| grep -- --dhcp-range=$BR_DHCP_SRV_RANGE \
			| awk '{print $1}'`
	if [ -z "$dnsmasq_pid" ]; then
		echo "failed to find dnsmasq process"
		exit 1
	fi
	kill "$dnsmasq_pid"
fi

for vm_num in `seq 1 "$VM_MAX_COUNT"`; do
	eval mac_addr='$MAC_ADDR'${vm_num}
	if [ -z "$mac_addr" ]; then
		continue
	fi
	eval tap='$TAP_DEV'$((vm_num - 1))
	[ -z "$tap" ] \
		&& _fail "TAP_DEV$((vm_num - 1)) not configured"
	ip link set dev $tap down || exit 1
	ip link set $tap nomaster || exit 1
	ip tuntap delete dev $tap mode tap || exit 1
done

ip link set dev $BR_DEV down || exit 1

if [ -n "$BR_IF" ]; then
	ip link set $BR_IF nomaster || exit 1
fi

if [ -n "$BR_ADDR" ]; then
	ip addr del $BR_ADDR dev $BR_DEV || exit 1
fi
ip link delete $BR_DEV type bridge || exit 1
