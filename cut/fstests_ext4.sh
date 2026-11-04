#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE S.A. 2021-2026, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

pam_paths=()
_rt_require_pam_mods pam_paths "pam_rootok.so" "pam_limits.so"
_rt_human_size_in_b "${FSTESTS_ZRAM_SIZE:-1G}" zram_bytes \
	|| _fail "failed to calculate memory resources"
# 2x multiplier for one test and one scratch zram. +2G as buffer
mem_rsc="$((2048 + (zram_bytes * 2 / 1048576)))M"

printf -v req_inst_bins 'bin %s\n' "${pam_paths[@]}"

rapido-cut --manifest /dev/stdin <<EOF
file /rapido-rsc/mem/${mem_rsc}
include manifest/fstests.fest

autorun autorun/lib/fstests.sh autorun/fstests_ext4.sh $*

$req_inst_bins
bin debugfs
bin dumpe2fs
bin e2fsck
bin e2image
bin e4defrag
bin fsck.ext4
bin mke2fs
bin mkfs.ext4
bin resize2fs
bin tune2fs

try-bin dump
try-bin restore
try-bin uuidgen

kmod ext4
EOF
