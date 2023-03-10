#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LINUX GmbH 2016, all rights reserved.

_vm_ar_env_check || exit 1

set -x

_vm_ar_hosts_create
_vm_ar_dyn_debug_enable

_fstests_users_groups_provision

mkdir -p /mnt/test
mount -t ceph ${CEPH_MON_ADDRESS_V1}:/ /mnt/test -o name=${CEPH_USER},secret=${CEPH_USER_KEY} \
	|| _fatal

[ -n "${FSTESTS_SRC}" ] || _fatal "FSTESTS_SRC unset"
[ -d "${FSTESTS_SRC}" ] || _fatal "$FSTESTS_SRC missing"

cfg="${FSTESTS_SRC}/configs/$(hostname -s).config"
cat > $cfg << EOF
MODULAR=0
TEST_DIR=/mnt/test
TEST_DEV=${CEPH_MON_ADDRESS_V1}:/
TEST_FS_MOUNT_OPTS="-o name=${CEPH_USER},secret=${CEPH_USER_KEY}"
FSTYP="ceph"
USE_KMEMLEAK=yes
EOF

set +x

cd "$FSTESTS_SRC" || _fatal
if [ -n "$FSTESTS_AUTORUN_CMD" ]; then
	eval "$FSTESTS_AUTORUN_CMD"
fi
