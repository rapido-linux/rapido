#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2016-2019, all rights reserved.
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

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_conf_setting BR1_DEV TAP_USER VM1_TAP_DEV1 VM2_TAP_DEV1

# cleanup on premature exit by executing whatever has been prepended to @unwind
unwind=""
trap "eval \$unwind" 0 1 2 3 15

ip link add $BR1_DEV type bridge || _fail "failed to add $BR1_DEV"
unwind="ip link delete $BR1_DEV type bridge; ${unwind}"
echo -n "+ created bridge $BR1_DEV"
if [ -n "$BR1_ADDR" ]; then
	ip addr add $BR1_ADDR dev $BR1_DEV || exit 1
	unwind="ip addr del $BR1_ADDR dev $BR1_DEV; ${unwind}"
	echo -n " with address $BR1_ADDR"
fi

if [ -n "$BR1_IF" ]; then
	ip link set $BR1_IF master $BR1_DEV || exit 1
	unwind="ip link set $BR1_IF nomaster; ${unwind}"
	echo -n ", connected to $BR1_IF"
fi
echo

# setup tap interfaces for VMs
ip tuntap add dev $VM1_TAP_DEV1 mode tap user $TAP_USER || exit 1
unwind="ip tuntap delete dev $VM1_TAP_DEV1 mode tap; ${unwind}"
ip link set $VM1_TAP_DEV1 master $BR1_DEV || exit 1
unwind="ip link set $VM1_TAP_DEV1 nomaster; ${unwind}"
echo "+ created $VM1_TAP_DEV1"

ip tuntap add dev $VM2_TAP_DEV1 mode tap user $TAP_USER || exit 1
unwind="ip tuntap delete dev $VM2_TAP_DEV1 mode tap; ${unwind}"
ip link set $VM2_TAP_DEV1 master $BR1_DEV || exit 1
unwind="ip link set $VM2_TAP_DEV1 nomaster; ${unwind}"
echo "+ created $VM2_TAP_DEV1"

ip link set dev $BR1_DEV up || exit 1
unwind="ip link set dev $BR1_DEV down; ${unwind}"
ip link set dev $VM1_TAP_DEV1 up || exit 1
unwind="ip link set dev $VM1_TAP_DEV1 down; ${unwind}"
ip link set dev $VM2_TAP_DEV1 up || exit 1
unwind="ip link set dev $VM2_TAP_DEV1 down; ${unwind}"

if [ -n "$BR1_DHCP_SRV_RANGE" ]; then
	hosts=
	[ -n "$VM1_IP_ADDR1" ] && \
		hosts="$hosts --dhcp-host=$VM1_MAC_ADDR1,$VM1_IP_ADDR1,${VM1_HOSTNAME:-vm1}"
	[ -n "$VM2_IP_ADDR1" ] && \
		hosts="$hosts --dhcp-host=$VM2_MAC_ADDR1,$VM2_IP_ADDR1,${VM2_HOSTNAME:-vm2}"
	dnsmasq --no-hosts --no-resolv \
		--pid-file=/var/run/rapido-dnsmasq-$$.pid \
		--bind-interfaces \
		--interface="$BR1_DEV" \
		--except-interface=lo \
		--dhcp-range="$BR1_DHCP_SRV_RANGE" \
		${hosts} || exit 1
	unwind="kill $(cat /var/run/rapido-dnsmasq-$$.pid); ${unwind}"
	echo "+ started DHCP server"
fi

# success! clear unwind
unwind=""
