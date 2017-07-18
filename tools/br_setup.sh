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

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

TUNCTL=$(which tunctl) || _fail "tunctl missing"

# cleanup on premature exit by executing whatever has been prepended to @unwind
unwind=""
trap "eval \$unwind" 0 1 2 3 15

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
$TUNCTL -u $TAP_USER -t $TAP_DEV0 || exit 1
unwind="$TUNCTL -d $TAP_DEV0; ${unwind}"
ip link set $TAP_DEV0 master $BR_DEV || exit 1
unwind="ip link set $TAP_DEV0 nomaster; ${unwind}"
echo "+ created $TAP_DEV0"

$TUNCTL -u $TAP_USER -t $TAP_DEV1 || exit 1
unwind="$TUNCTL -d $TAP_DEV1; ${unwind}"
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
