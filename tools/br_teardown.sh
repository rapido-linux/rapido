#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2017-2019, all rights reserved.
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

_rt_require_conf_setting BR1_DEV VM1_TAP_DEV1 VM2_TAP_DEV1

set -x

if [ -n "$BR1_DHCP_SRV_RANGE" ]; then
	dnsmasq_pid=`ps -eo pid,args | grep -v grep | grep dnsmasq \
			| grep -- --interface=$BR1_DEV \
			| grep -- --dhcp-range=$BR1_DHCP_SRV_RANGE \
			| awk '{print $1}'`
	if [ -z "$dnsmasq_pid" ]; then
		echo "failed to find dnsmasq process"
		exit 1
	fi
	kill "$dnsmasq_pid"
fi

ip link set dev $VM2_TAP_DEV1 down || exit 1
if [ -n "$VM2_TAP_DEV2" ]; then
	ip link set dev $VM2_TAP_DEV2 down || exit 1
fi
ip link set dev $VM1_TAP_DEV1 down || exit 1
if [ -n "$VM1_TAP_DEV2" ]; then
	ip link set dev $VM1_TAP_DEV2 down || exit 1
fi

if [ -z "$BR1_DEV_SKIP_PROVISON" ]; then
	ip link set dev $BR1_DEV down || exit 1
fi

if [ -n "$BR2_DEV" ] && [ -z "$BR2_DEV_SKIP_PROVISON" ]; then
	ip link set dev $BR2_DEV down || exit 1
fi

ip link set $VM2_TAP_DEV1 nomaster || exit 1
ip tuntap delete dev $VM2_TAP_DEV1 mode tap || exit 1
if [ -n "$VM2_TAP_DEV2" ]; then
	ip link set $VM2_TAP_DEV2 nomaster || exit 1
	ip tuntap delete dev $VM2_TAP_DEV2 mode tap || exit 1
fi

ip link set $VM1_TAP_DEV1 nomaster || exit 1
ip tuntap delete dev $VM1_TAP_DEV1 mode tap || exit 1
if [ -n "$VM1_TAP_DEV2" ]; then
	ip link set $VM1_TAP_DEV2 nomaster || exit 1
	ip tuntap delete dev $VM1_TAP_DEV2 mode tap || exit 1
fi

if [ -z "$BR1_DEV_SKIP_PROVISON" ]; then
	if [ -n "$BR1_IF" ]; then
		ip link set $BR1_IF nomaster || exit 1
	fi

	if [ -n "$BR1_ADDR" ]; then
		ip addr del $BR1_ADDR dev $BR1_DEV || exit 1
	fi
	ip link delete $BR1_DEV type bridge || exit 1
fi

if [ -n "$BR2_DEV" ] && [ -z "$BR2_DEV_SKIP_PROVISON" ]; then
	if [ -n "$BR2_IF" ]; then
		ip link set $BR2_IF nomaster || exit 1
	fi

	if [ -n "$BR2_ADDR" ]; then
		ip addr del $BR2_ADDR dev $BR2_DEV || exit 1
	fi
	ip link delete $BR2_DEV type bridge || exit 1

fi
