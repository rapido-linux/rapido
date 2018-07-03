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

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

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

function _br_tap_setup() {
	local tap_dev="$1"

	ip tuntap add dev $tap_dev mode tap user $TAP_USER || _fail
	unwind="ip tuntap delete dev $tap_dev mode tap; ${unwind}"

	ip link set $tap_dev master $BR_DEV || _fail
	unwind="ip link set $tap_dev nomaster; ${unwind}"

	ip link set dev $tap_dev up || exit 1
	unwind="ip link set dev $tap_dev down; ${unwind}"

	echo "+ created $tap_dev"
}

dhcp_hosts=""

# setup tap interfaces for VMs
for vm_num in `seq 1 "$VM_MAX_COUNT"`; do
	eval mac_addr='$MAC_ADDR'${vm_num}
	if [ -z "$mac_addr" ]; then
		echo "MAC_ADDR${vm_num} not configured"
		continue
	fi
	eval tap='$TAP_DEV'$((vm_num - 1))
	[ -z "$tap" ] \
		&& _fail "TAP_DEV$((vm_num - 1)) not configured"

	_br_tap_setup "$tap"

	[ -z "$BR_DHCP_SRV_RANGE" ] \
		&& continue	# no DHCP server

	eval ip='$IP_ADDR'${vm_num}
	[ -z "$ip" ] \
		&& continue	# no VM IP assigned for DHCP

	# add an explicit DHCP server host entry for this VM
	dhcp_hosts="$dhcp_hosts --dhcp-host=${mac_addr},${ip}"

	eval hn='$HOSTNAME'${vm_num}
	[ -n "$hn" ] \
		&& dhcp_hosts="${dhcp_hosts},${hn}" # append explicit hostname
done

ip link set dev $BR_DEV up || exit 1
unwind="ip link set dev $BR_DEV down; ${unwind}"

if [ -n "$BR_DHCP_SRV_RANGE" ]; then
	dnsmasq --no-hosts --no-resolv \
		--pid-file=/var/run/rapido-dnsmasq-$$.pid \
		--bind-interfaces \
		--interface="$BR_DEV" \
		--except-interface=lo \
		--dhcp-range="$BR_DHCP_SRV_RANGE" \
		${dhcp_hosts} || exit 1
	unwind="kill $(cat /var/run/rapido-dnsmasq-$$.pid); ${unwind}"
	echo "+ started DHCP server"
fi

# success! clear unwind
unwind=""
