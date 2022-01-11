#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2016, all rights reserved.

_vm_ar_env_check || exit 1

set -x

_ceph_rbd_map

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
