#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE S.A. 2016-2026, all rights reserved.
rapido-cut --manifest /dev/stdin <<EOF
file /rapido-rsc/mem/2048M

include net.fest

autorun autorun/lio_local.sh $*

bin blockdev
bin cat
bin dd
bin df
bin dmesg
bin dmsetup
bin find
bin grep
bin hostname
bin ln
bin losetup
bin ls
bin mkdir
bin mkfs.xfs
bin nc
bin ps
bin rmdir
bin sha256sum
bin sleep
bin strace
bin stty
bin tail
bin truncate

file /usr/lib/udev/rules.d/95-dm-notify.rules /usr/lib/udev/rules.d/95-dm-notify.rules

kmod iscsi_target_mod
kmod target_core_iblock
kmod target_core_file
kmod dm-delay
kmod loop
EOF
