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

# This script removes all addresses from $BR_IF, creates $BR_DEV and
# subsequently adds all previous $BR_IF addresses to the new $BR_DEV.
# The routing table is also replaced, with all $BR_IF routes transferring
# to $BR_DEV.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

function _apply_routes() {
	local action="$1"
	local dev="$2"
	local routes_file="$3"
	local line=""

	while read -r line; do
		# ignore failures - addr changes can add/delete routes
		ip route $action $line dev $dev || continue
		if [ "$action" == "add" ]; then
			unwind="ip route del $line dev $dev; ${unwind}"
		elif [ "$action" == "del" ]; then
			unwind="ip route add $line dev $dev; ${unwind}"
		else
			exit 1
		fi
	done < "$routes_file"
}

function _apply_addrs() {
	local action="$1"
	local dev="$2"
	local addrs_file="$3"
	local line=""

	while read -r line; do
		ip addr $action $line dev $dev || exit 1
		if [ "$action" == "add" ]; then
			unwind="ip addr del $line dev $dev; ${unwind}"
		elif [ "$action" == "del" ]; then
			unwind="ip addr add $line dev $dev; ${unwind}"
		else
			exit 1
		fi
	done < $addrs_file
}

[ -z "$BR_ADDR" ] || _fail "BR_ADDR setting incompatible with ip takeover"
[ -n "$BR_DEV" ] || _fail "BR_DEV required for IP takeover"
[ -n "$BR_IF" ] || _fail "BR_IF required for IP takeover"

set -x

BR_IF_DUMP_DIR=`mktemp --tmpdir -d ${BR_IF}_addr_dump.XXXXXXXXXX` || exit 1

# cleanup on premature exit by executing whatever has been prepended to @unwind
unwind="rmdir $BR_IF_DUMP_DIR"
trap "eval \$unwind" 0 1 2 3 15

ip link add $BR_DEV type bridge || exit 1
unwind="ip link delete $BR_DEV type bridge; ${unwind}"

ip link set dev $BR_DEV down || exit 1

ip -6 addr list dev $BR_IF \
	| sed -n 's#\(scope \w*\).*$#\1#; s#\s*inet6\s*##p' \
	> ${BR_IF_DUMP_DIR}/inet6_addrs || exit 1
unwind="rm -f ${BR_IF_DUMP_DIR}/inet6_addrs; ${unwind}"

ip -4 addr list dev $BR_IF \
	| sed -n 's#\(scope \w*\).*$#\1#; s#\s*inet\s*##p' \
	> ${BR_IF_DUMP_DIR}/inet4_addrs || exit 1
unwind="rm -f ${BR_IF_DUMP_DIR}/inet4_addrs; ${unwind}"

ip route list dev $BR_IF > ${BR_IF_DUMP_DIR}/routes
unwind="rm -f ${BR_IF_DUMP_DIR}/routes; ${unwind}"

_apply_routes del "$BR_IF" "${BR_IF_DUMP_DIR}/routes" || exit 1

_apply_addrs del "$BR_IF" "${BR_IF_DUMP_DIR}/inet6_addrs" || exit 1
_apply_addrs del "$BR_IF" "${BR_IF_DUMP_DIR}/inet4_addrs" || exit 1

ip link set $BR_IF master $BR_DEV || exit 1
unwind="ip link set $BR_IF nomaster; ${unwind}"

_apply_addrs add "$BR_DEV" "${BR_IF_DUMP_DIR}/inet6_addrs" || exit 1
_apply_addrs add "$BR_DEV" "${BR_IF_DUMP_DIR}/inet4_addrs" || exit 1

ip link set dev $BR_DEV up
unwind="ip link set dev $BR_DEV down; ${unwind}"

_apply_routes add "$BR_DEV" "${BR_IF_DUMP_DIR}/routes" || exit 1

# setup tap interfaces for VMs
ip tuntap add dev $TAP_DEV0 mode tap user $TAP_USER || exit 1
unwind="ip tuntap delete dev $TAP_DEV0 mode tap; ${unwind}"
ip link set $TAP_DEV0 master $BR_DEV || exit 1
unwind="ip link set $TAP_DEV0 nomaster; ${unwind}"
ip link set $TAP_DEV0 up
unwind="ip link set $TAP_DEV0 down; ${unwind}"

ip tuntap add dev $TAP_DEV1 mode tap user $TAP_USER || exit 1
unwind="ip tuntap delete dev $TAP_DEV1 mode tap; ${unwind}"
ip link set $TAP_DEV1 master $BR_DEV || exit 1
unwind="ip link set $TAP_DEV1 nomaster; ${unwind}"
ip link set $TAP_DEV1 up
unwind="ip link set $TAP_DEV1 down; ${unwind}"

rm ${BR_IF_DUMP_DIR}/routes ${BR_IF_DUMP_DIR}/*addrs
rmdir ${BR_IF_DUMP_DIR}
# success! clear unwind
unwind="echo success"
