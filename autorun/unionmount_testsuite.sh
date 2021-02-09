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

num_devs="2"
modprobe zram num_devices="$num_devs" || _fatal "failed to load zram module"

_vm_ar_dyn_debug_enable

mkdir -p /base /lower /upper /mnt

for lowerfs in "xfs" "btrfs"; do
	for upperfs in "xfs" "btrfs"; do
		echo "running tests with lowerfs=${lowerfs} upperfs=${upperfs}"
		for ((i=0; i < $num_devs; i++)); do
			echo "1" > /sys/block/zram${i}/reset || _fatal
			echo "1G" > /sys/block/zram${i}/disksize || _fatal
		done

		mkfs.${lowerfs} "/dev/zram0" || _fatal
		echo /dev/zram0 /lower $lowerfs noauto > /etc/fstab
		mkfs.${upperfs} "/dev/zram1" || _fatal
		echo /dev/zram1 /upper $upperfs noauto >> /etc/fstab

		pushd "$UNIONMOUNT_TESTSUITE_SRC"
		./run --ov || _fatal "test failed"
		popd
		cat /proc/mounts
		umount /base /lower /upper /mnt
	done
done
echo "all tests completed"
shutdown
