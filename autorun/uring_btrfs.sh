#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2021-2022, all rights reserved.

_vm_ar_env_check || exit 1

set -x

modprobe zram num_devices="1" || _fatal "failed to load zram module"

_vm_ar_dyn_debug_enable

echo "1G" > /sys/block/zram0/disksize || _fatal "failed to set zram disksize"

mkfs.btrfs /dev/zram0 || _fatal "mkfs failed"

mkdir -p /mnt
mount -t btrfs /dev/zram0 /mnt || _fatal
chmod 777 /mnt || _fatal

set +x

# send_recvmsg test needs loopback networking
ip link set dev lo up

# liburing tests run from CWD so we unfortunately have to move them over
mv ${LIBURING_SRC}/test /mnt || _fatal
cd /mnt/test || _fatal

cat <<EOF
To run a test:
  ./runtests.sh <test_name>

E.g. to run all tests on boot:
  ./rapido cut -x './runtests.sh \$(cat /uring_tests.manifest)' uring-btrfs
EOF
