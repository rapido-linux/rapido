#!/bin/bash
#
# Copyright (C) SUSE LLC 2021, all rights reserved.
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

if [ -n "$EXFAT_PROGS_SRC" ]; then
	export PATH="${PATH}:${EXFAT_PROGS_SRC}/mkfs:${EXFAT_PROGS_SRC}/fsck"
	export PATH="${PATH}:${EXFAT_PROGS_SRC}/dump:${EXFAT_PROGS_SRC}/tune"
fi

num_devs="2"
modprobe zram num_devices="${num_devs}" || _fatal "failed to load zram module"

_vm_ar_hosts_create
_vm_ar_dyn_debug_enable

xid="2000"	# xfstests requires a few preexisting users/groups
for ug in fsgqa fsgqa2 123456-fsgqa; do
	echo "${ug}:x:${xid}:${xid}:${ug} user:/:/sbin/nologin" >> /etc/passwd
	echo "${ug}:x:${xid}:" >> /etc/group
	((xid++))
done

filesystem="exfat"

[ -n "${FSTESTS_ZRAM_SIZE}" ] || FSTESTS_ZRAM_SIZE="1G"

for i in $(seq 0 $((num_devs - 1))); do
	echo "${FSTESTS_ZRAM_SIZE}" > /sys/block/zram${i}/disksize \
		|| _fatal "failed to set zram disksize"
done

mkdir -p /mnt/test
mkdir -p /mnt/scratch

mkfs.${filesystem} /dev/zram0 || _fatal "mkfs failed"
mount -t $filesystem /dev/zram0 /mnt/test || _fatal
# xfstests can handle scratch mkfs+mount

[ -n "${FSTESTS_SRC}" ] || _fatal "FSTESTS_SRC unset"
[ -d "${FSTESTS_SRC}" ] || _fatal "$FSTESTS_SRC missing"

cfg="${FSTESTS_SRC}/configs/$(hostname -s).config"
cat > $cfg << EOF
MODULAR=0
TEST_DIR=/mnt/test
TEST_DEV=/dev/zram0
SCRATCH_MNT=/mnt/scratch
SCRATCH_DEV=/dev/zram1
USE_KMEMLEAK=yes
FSTYP=${filesystem}
EOF

set +x

echo "$filesystem filesystem ready for FSQA"

if [ -n "$FSTESTS_AUTORUN_CMD" ]; then
	cd ${FSTESTS_SRC} || _fatal
	eval "$FSTESTS_AUTORUN_CMD"
fi
