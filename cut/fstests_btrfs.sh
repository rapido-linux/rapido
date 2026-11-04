#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE S.A. 2018-2026, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

req_inst=()
_rt_require_btrfs_progs req_inst
_rt_require_pam_mods req_inst "pam_rootok.so" "pam_limits.so"
_rt_human_size_in_b "${FSTESTS_ZRAM_SIZE:-1G}" zram_bytes \
	|| _fail "failed to calculate memory resources"
# need enough memory for five zram devices
mem_rsc="$((3072 + (zram_bytes * 5 / 1048576)))M"

printf -v req_inst_bins 'bin %s\n' "${req_inst[@]}"

rapido-cut --manifest /dev/stdin <<EOF
file /rapido-rsc/mem/${mem_rsc}
include manifest/fstests.fest

autorun autorun/lib/fstests.sh autorun/fstests_btrfs.sh $*

bin mkfs.ext4
$req_inst_bins

kmod btrfs
kmod raid6_pq
kmod xxhash_generic
# needed for tests/btrfs/012 and tests/btrfs/136
try-kmod ext4
EOF
