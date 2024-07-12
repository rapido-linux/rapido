#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LINUX GmbH 2016-2019, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_conf_setting BR_DEV TAP_USER TAP_DEV0 TAP_DEV1

# cleanup on premature exit by executing whatever has been prepended to @unwind
unwind=""
trap "eval \$unwind" 0

ip link add $BR_DEV type bridge || _fail "failed to add $BR_DEV"
unwind="ip link delete $BR_DEV type bridge; ${unwind}"
echo -n "+ created bridge $BR_DEV"
if [ -n "$BR_ADDR" ]; then
	ip addr add $BR_ADDR dev $BR_DEV || exit 1
	unwind="ip addr del $BR_ADDR dev $BR_DEV; ${unwind}"
	echo -n " with address $BR_ADDR"
fi

if [ -n "$BR_IF" ]; then
	ip link set $BR_IF master $BR_DEV || exit 1
	unwind="ip link set $BR_IF nomaster; ${unwind}"
	echo -n ", connected to $BR_IF"
fi
echo

# setup tap interfaces for VMs
ip tuntap add dev $TAP_DEV0 mode tap user $TAP_USER || exit 1
unwind="ip tuntap delete dev $TAP_DEV0 mode tap; ${unwind}"
ip link set $TAP_DEV0 master $BR_DEV || exit 1
unwind="ip link set $TAP_DEV0 nomaster; ${unwind}"
echo "+ created $TAP_DEV0"

ip tuntap add dev $TAP_DEV1 mode tap user $TAP_USER || exit 1
unwind="ip tuntap delete dev $TAP_DEV1 mode tap; ${unwind}"
ip link set $TAP_DEV1 master $BR_DEV || exit 1
unwind="ip link set $TAP_DEV1 nomaster; ${unwind}"
echo "+ created $TAP_DEV1"

ip link set dev $BR_DEV up || exit 1
unwind="ip link set dev $BR_DEV down; ${unwind}"
ip link set dev $TAP_DEV0 up || exit 1
unwind="ip link set dev $TAP_DEV0 down; ${unwind}"
ip link set dev $TAP_DEV1 up || exit 1
unwind="ip link set dev $TAP_DEV1 down; ${unwind}"

if [ -n "$BR_DHCP_SRV_RANGE" ]; then
	hosts=
	[ -n "$IP_ADDR1" ] && \
		hosts="$hosts --dhcp-host=$MAC_ADDR1,$IP_ADDR1,${HOSTNAME1:-vm1}"
	[ -n "$IP_ADDR2" ] && \
		hosts="$hosts --dhcp-host=$MAC_ADDR2,$IP_ADDR2,${HOSTNAME2:-vm2}"
	dnsmasq --no-hosts --no-resolv \
		--pid-file=/var/run/rapido-dnsmasq-$$.pid \
		--bind-interfaces \
		--interface="$BR_DEV" \
		--except-interface=lo \
		--dhcp-range="$BR_DHCP_SRV_RANGE" \
		${hosts} || exit 1
	unwind="kill $(cat /var/run/rapido-dnsmasq-$$.pid); ${unwind}"
	echo "+ started DHCP server"
fi

# success! clear unwind
unwind=""
