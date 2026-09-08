#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2016-2022, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

req_inst=()
_rt_require_pam_mods req_inst "pam_rootok.so" "pam_limits.so"
_rt_human_size_in_b "${FSTESTS_ZRAM_SIZE:-1G}" zram_bytes \
	|| _fail "failed to calculate memory resources"
# 2x multiplier for one test and one scratch zram. +2G as buffer
mem_rsc="$((2048 + (zram_bytes * 2 / 1048576)))M"

man_deps=(man /etc/manpath.config \
	  $(man --path xfs_io xfs_spaceman xfs_db xfs_quota))
[[ "${man_deps[*]}" == "${man_deps[*]%.gz}" ]] || man_deps+=(zcat)
[[ "${man_deps[*]}" == "${man_deps[*]%.bz2}" ]] || man_deps+=(bzcat)
[[ "${man_deps[*]}" == "${man_deps[*]%.xz}" ]] || man_deps+=(xzcat)

# xfs/122: pull in compiler and xfs headers
_rt_require_gcc req_inst stdio.h xfs/xfs.h xfs/xfs_types.h xfs/xfs_fs.h \
	xfs/xfs_arch.h xfs/xfs_format.h xfs/linux.h
# xfs/122: catch any headers which might be new
req_inst+=(/usr/include/xfs/*.h)

printf -v req_inst_bins 'bin %s\n' "${man_deps[@]}" "${req_inst[@]}"

PATH="target/release:${PATH}"
rapido-cut --manifest /dev/stdin <<EOF
file /rapido-rsc/mem/${mem_rsc}
include manifest/fstests.fest

autorun autorun/lib/fstests.sh autorun/fstests_xfs.sh $*

$req_inst_bins
bin comm
bin mkfs.xfs
bin xfs_bmap
bin xfs_db
bin xfs_freeze
bin xfs_fsr
bin xfs_growfs
bin xfs_info
bin xfs_io
bin xfs_logprint
bin xfs_mdrestore
bin xfs_metadump
bin xfs_mkfile
bin xfs_quota
bin xfs_repair
bin xfs_spaceman

try-bin indent
try-bin xfsdump
try-bin xfsinvutil
try-bin xfsrestore

kmod xfs
EOF
