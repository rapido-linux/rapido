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

_vm_ar_env_check || exit 1

set -x

modprobe zram num_devices="1" || _fatal "failed to load zram module"

_vm_ar_dyn_debug_enable

echo "1G" > /sys/block/zram0/disksize || _fatal "failed to set zram disksize"

addr=""
ip link show eth0 | grep $VM1_MAC_ADDR1 &> /dev/null
if [ $? -eq 0 ]; then
	addr="${IP_ADDR1}"
fi

ip link show eth0 | grep $VM2_MAC_ADDR1 &> /dev/null
if [ $? -eq 0 ]; then
	addr="${IP_ADDR2}"
fi

[ -z "$addr" ] && _fatal "VM network config missing"

# create IPC directory
mkdir /var/run/tgtd || _fatal

${TGT_SRC}/usr/tgtd --debug 1 --iscsi portal=${addr}:3260 || _fatal

${TGT_SRC}/usr/tgtadm --lld iscsi --mode target --op new \
	--tid 1 --targetname $TARGET_IQN || _fatal

${TGT_SRC}/usr/tgtadm --lld iscsi --op bind --mode target \
	--tid 1 --initiator-address ALL || _fatal

for initiator in $INITIATOR_IQNS; do
	${TGT_SRC}/usr/tgtadm --lld iscsi --op bind --mode target \
		--tid 1 --initiator-name "$initiator" || _fatal
done

# TGT reserves LUN0, so create LUN1 with zram backing device
lun="1"
${TGT_SRC}/usr/tgtadm --lld iscsi --op new --mode=logicalunit \
	--tid 1 --lun "$lun" --backing-store /dev/zram0 || _fatal

set +x

echo "target ready at: iscsi://${addr}:3260/${TARGET_IQN}/${lun}"
