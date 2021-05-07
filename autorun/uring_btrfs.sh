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

modprobe zram num_devices="1" || _fatal "failed to load zram module"

_vm_ar_dyn_debug_enable

echo "1G" > /sys/block/zram0/disksize || _fatal "failed to set zram disksize"

mkfs.btrfs /dev/zram0 || _fatal "mkfs failed"

mkdir -p /mnt
mount -t btrfs /dev/zram0 /mnt || _fatal
chmod 777 /mnt || _fatal

set +x

# liburing tests run from CWD so we unfortunately have to move them over
mv ${LIBURING_SRC}/test /mnt || _fatal
cd /mnt/test || _fatal

cat <<EOF
To run a test:
  ./runtests.sh <test_name>

E.g. to run all tests on boot:
  ./rapido cut -x './runtests.sh \$(cat /uring_tests.manifest)' uring-btrfs
EOF
