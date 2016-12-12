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
set -x

BRCTL=$(which brctl)
if [ -z "$BRCTL" ]; then
    echo "Could not find brctl...rerun as root or install the bridge-tools package"
    exit 1
fi

TUNCTL=$(which tunctl)
if [ -z "$TUNCTL" ]; then
    echo "Could not find tunctl...rerun as root or install the tunctl package"
    exit 1
fi

$BRCTL addbr $BR_DEV || exit 1
if [ -n "$BR_ADDR" ]; then
	ip addr add $BR_ADDR dev $BR_DEV || exit 1
fi

if [ -n "$BR_IF" ]; then
	$BRCTL addif $BR_DEV $BR_IF || exit 1
fi

# setup tap interfaces for VMs
$TUNCTL -u $TAP_USER -t $TAP_DEV0 || exit 1
$BRCTL addif $BR_DEV $TAP_DEV0 || exit 1

$TUNCTL -u $TAP_USER -t $TAP_DEV1 || exit 1
$BRCTL addif $BR_DEV $TAP_DEV1 || exit 1

ip link set dev $BR_DEV up || exit 1
ip link set dev $TAP_DEV0 up || exit 1
ip link set dev $TAP_DEV1 up || exit 1

if [ -n "$BR_DHCP_SRV_RANGE" ]; then
	dnsmasq --no-hosts --no-resolv \
		--interface="$BR_DEV" \
		--dhcp-range="$BR_DHCP_SRV_RANGE" || exit 1
fi
