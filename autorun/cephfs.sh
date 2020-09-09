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

_vm_ar_env_check || exit 1

set -x

_vm_ar_dyn_debug_enable

mkdir -p /mnt/cephfs
mount -t ceph ${CEPH_MON_ADDRESS_V1}:/ /mnt/cephfs \
	-o name=${CEPH_USER},secret=${CEPH_USER_KEY} || _fatal
cd /mnt/cephfs || _fatal
set +x
