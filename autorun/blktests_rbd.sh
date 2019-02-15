#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2017, all rights reserved.
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

# path to blktests within the initramfs
BLKTESTS_DIR="/blktests"
[ -d "$BLKTESTS_DIR" ] || _fatal "blktests missing"

# map rbd device
_vm_ar_rbd_map

# this path is reliant on the rbd udev rule to setup the link
CEPH_RBD_DEV=/dev/rbd/${CEPH_RBD_POOL}/${CEPH_RBD_IMAGE}
[ -L $CEPH_RBD_DEV ] || _fatal

_vm_ar_dyn_debug_enable

echo "TEST_DEVS=(${CEPH_RBD_DEV})" > ${BLKTESTS_DIR}/config

set +x

echo "$CEPH_RBD_DEV mapped and ready for ${BLKTESTS_DIR}/check"

if [ -n "$BLKTESTS_AUTORUN_CMD" ]; then
	cd ${BLKTESTS_DIR} || _fatal
	eval "$BLKTESTS_AUTORUN_CMD"
fi
