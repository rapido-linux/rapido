#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2021-2022, all rights reserved.

_vm_ar_env_check || exit 1

set -x

modprobe virtio_blk
modprobe zram num_devices="0" || _fatal "failed to load zram module"

_vm_ar_hosts_create
_vm_ar_dyn_debug_enable

xid="2000"	# xfstests requires a few preexisting users/groups
for ug in fsgqa fsgqa2 123456-fsgqa; do
	echo "${ug}:x:${xid}:${xid}:${ug} user:/:/sbin/nologin" >> /etc/passwd
	echo "${ug}:x:${xid}:" >> /etc/group
	((xid++))
done

fstests_cfg="${FSTESTS_SRC}/configs/$(hostname -s).config"
cat > "$fstests_cfg" << EOF
MODULAR=0
TEST_DIR=/mnt/test
SCRATCH_MNT=/mnt/scratch
USE_KMEMLEAK=yes
FSTYP=ext4
EOF
_fstests_devs_provision "$fstests_cfg"
. "$fstests_cfg"

mkdir -p "$TEST_DIR" "$SCRATCH_MNT"
mkfs."${FSTYP}" -F "$TEST_DEV" || _fatal "mkfs failed"
mount -t "$FSTYP" "$TEST_DEV" "$TEST_DIR" || _fatal
# xfstests can handle scratch mkfs+mount

# See kvm-xfstests/test-appliance/files/root/fs/ext4/exclude in xfstests-bld
# (https://git.kernel.org/pub/scm/fs/ext2/xfstests-bld.git) for reasons why
# these tests are expected to fail.
cat > "${FSTESTS_SRC}/configs/ext4.exclude" << EOF
generic/042
generic/044
generic/045
generic/046
generic/223
generic/388
generic/392
EOF

e2fsck_bin="$(type -P e2fsck)"	# fsck.ext3 needed for tests/ext4/044
ln -s "$e2fsck_bin" "${e2fsck_bin/e2fsck/fsck.ext3}"

# fstests generic/131 needs loopback networking
ip link set dev lo up

set +x

echo "$FSTYP filesystem ready for FSQA"

cd "$FSTESTS_SRC" || _fatal
if [ -n "$FSTESTS_AUTORUN_CMD" ]; then
	eval "$FSTESTS_AUTORUN_CMD"
fi
