#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2018, all rights reserved.
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

if [ ! -f /vm_autorun.env ]; then
	echo "Error: autorun scripts must be run from within an initramfs VM"
	exit 1
fi

. /vm_autorun.env

set -x

modprobe iscsi_tcp

_vm_ar_dyn_debug_enable

mkdir -p /etc/iscsi
[ -n "$INITIATOR_IQNS" ] \
	|| _fatal "INITIATOR_IQNS config required for InitiatorName"
inames=( $INITIATOR_IQNS )
echo "InitiatorName=${inames[0]}" > /etc/iscsi/initiatorname.iscsi

echo ${OPENISCSI_SRC}/libopeniscsiusr >> /etc/ld.so.conf
export PATH="${PATH}:${OPENISCSI_SRC}/usr"

iscsid || _fatal

[ -n "$INITIATOR_DISCOVERY_ADDR" ] \
	|| _fatal "INITIATOR_DISCOVERY_ADDR config required for SendTargets"
iscsiadm -m discovery -t sendtargets -p $INITIATOR_DISCOVERY_ADDR || _fatal
# login to all discovered targets
iscsiadm -m node -l all || _fatal
set +x
