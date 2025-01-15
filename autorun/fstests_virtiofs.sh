#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2025, all rights reserved

_vm_ar_env_check || exit 1

set -x

_vm_ar_hosts_create
_vm_ar_dyn_debug_enable

_fstests_users_groups_provision

# as per cut script, expect a "TEST_DEV" tagged virtiofs share
virtiofs_tag="TEST_DEV"
[[ -n "$VIRTIOFS_MOUNT_OPTS" ]] && mount_args="-o${VIRTIOFS_MOUNT_OPTS}"

mkdir -p /mnt/test
mount -t virtiofs "$virtiofs_tag" /mnt/test \
	$mount_args || _fatal

[[ -n "$FSTESTS_SRC" ]] || _fatal "FSTESTS_SRC unset"
[[ -d "$FSTESTS_SRC" ]] || _fatal "$FSTESTS_SRC missing"

cfg="${FSTESTS_SRC}/configs/$(hostname -s).config"
cat > $cfg << EOF
MODULAR=0
TEST_DIR=/mnt/test
TEST_DEV=${virtiofs_tag}
TEST_FS_MOUNT_OPTS="$mount_args"
FSTYP="virtiofs"
USE_KMEMLEAK=yes
EOF

set +x

cd "$FSTESTS_SRC" || _fatal
[[ -n $FSTESTS_AUTORUN_CMD ]] && eval "$FSTESTS_AUTORUN_CMD"
