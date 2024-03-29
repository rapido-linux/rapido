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

/usr/lib/systemd/systemd-udevd --daemon

modprobe nbd nbds_max=1

_vm_ar_dyn_debug_enable

sed -i "s#keyring = .*#keyring = /etc/ceph/keyring#g; \
	s#admin socket = .*##g; \
	s#run dir = .*#run dir = /var/run/#g; \
	s#log file = .*#log file = /var/log/\$name.\$pid.log#g" \
	/etc/ceph/ceph.conf

# checked during cut
rbd_nbd_bin="${CEPH_SRC}/build/bin/rbd-nbd"
[ -x "$rbd_nbd_bin" ] || _fatal "rbd-nbd executable missing at $rbd_nbd_bin"

$rbd_nbd_bin map ${CEPH_RBD_POOL}/${CEPH_RBD_IMAGE} --id ${CEPH_USER} \
	-m ${CEPH_MON_ADDRESS_V1} --key=${CEPH_USER_KEY} || _fatal "rbd-nbd map failed"

set +x
