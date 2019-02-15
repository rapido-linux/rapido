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

if [ ! -f /vm_autorun.env ]; then
	echo "Error: autorun scripts must be run from within an initramfs VM"
	exit 1
fi

. /vm_autorun.env
. /vm_ceph.env

set -x

# map rbd device
_vm_ar_rbd_map

# this path is reliant on the rbd udev rule to setup the link
CEPH_RBD_DEV=/dev/rbd/${CEPH_RBD_POOL}/${CEPH_RBD_IMAGE}
[ -L $CEPH_RBD_DEV ] || _fatal

modprobe configfs
_vm_ar_configfs_mount

modprobe nvme-core
modprobe nvme-fabrics
modprobe nvme-loop
modprobe nvmet

_vm_ar_dyn_debug_enable

nvmet_subsystem="nvmf-test"
mkdir -p /sys/kernel/config/nvmet/subsystems/${nvmet_subsystem} || _fatal
cd /sys/kernel/config/nvmet/subsystems/${nvmet_subsystem} || _fatal
echo 1 > attr_allow_any_host || _fatal
mkdir namespaces/1 || _fatal
cd namespaces/1 || _fatal
echo -n $CEPH_RBD_DEV > device_path || _fatal
echo 1 > enable || _fatal

mkdir /sys/kernel/config/nvmet/ports/1 || _fatal
cd /sys/kernel/config/nvmet/ports/1 || _fatal
echo loop > addr_trtype || _fatal

ln -s /sys/kernel/config/nvmet/subsystems/${nvmet_subsystem} \
	subsystems/${nvmet_subsystem} || _fatal

echo "transport=loop,nqn=${nvmet_subsystem}" > /dev/nvme-fabrics || _fatal

set +x

echo "RBD mapped at: $CEPH_RBD_DEV, NVMe mapped"
