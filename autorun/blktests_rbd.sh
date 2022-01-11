#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2017, all rights reserved.

_vm_ar_env_check || exit 1

set -x

_ceph_rbd_map

# this path is reliant on the rbd udev rule to setup the link
CEPH_RBD_DEV=/dev/rbd/${CEPH_RBD_POOL}/${CEPH_RBD_IMAGE}
[ -L $CEPH_RBD_DEV ] || _fatal

_vm_ar_dyn_debug_enable

echo "TEST_DEVS=(${CEPH_RBD_DEV})" > "${BLKTESTS_SRC}/config"

set +x

echo "$CEPH_RBD_DEV mapped and ready for ${BLKTESTS_SRC}/check"

cd "$BLKTESTS_SRC" || _fatal
if [ -n "$BLKTESTS_AUTORUN_CMD" ]; then
	eval "$BLKTESTS_AUTORUN_CMD"
fi
