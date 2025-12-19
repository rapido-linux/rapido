#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE S.A. 2018-2025, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_fstests
# rapido-cut doesn't support globbing, so do it here.
req_inst=(${FSTESTS_SRC}/ltp/* ${FSTESTS_SRC}/src/* \
	${FSTESTS_SRC}/src/log-writes/* ${FSTESTS_SRC}/src/aio-dio-regress/*)
_rt_require_btrfs_progs req_inst
_rt_require_pam_mods req_inst "pam_rootok.so" "pam_limits.so"
_rt_human_size_in_b "${FSTESTS_ZRAM_SIZE:-1G}" zram_bytes \
	|| _fail "failed to calculate memory resources"
# need enough memory for five zram devices
mem_rsc="$((3072 + (zram_bytes * 5 / 1048576)))M"

PATH="target/release:${PATH}"
rapido-cut \
	--autorun "autorun/lib/fstests.sh autorun/fstests_btrfs.sh $*" \
	--include "dracut.conf.d/.empty /rapido-rsc/mem/${mem_rsc}" \
	--install "ls cat mkdir cp mv rm ln sed readlink sleep \
		   umount findmnt dmesg uname \
		   tail blockdev ps rmdir resize dd grep find df sha256sum \
		   strace mkfs mkfs.ext4 e2fsck tune2fs shuf free ip su \
		   which perl awk bc touch cut chmod true false unlink \
		   mktemp getfattr setfattr chacl attr killall hexdump sync \
		   id sort uniq date expr tac diff head dirname seq \
		   basename tee egrep yes mkswap timeout realpath blkdiscard \
		   fstrim logger dmsetup chattr lsattr cmp stat \
		   hostname getconf md5sum \
		   od wc getfacl setfacl tr xargs sysctl link truncate quota \
		   repquota setquota quotacheck quotaon pvremove vgremove \
		   xfs_mkfile xfs_db xfs_io wipefs filefrag losetup \
		   chgrp du fgrep pgrep tar rev kill \
		   swapon swapoff xfs_freeze fsck ${req_inst[*]}" \
	--try-install "resize dbench /usr/share/dbench/client.txt duperemove \
		       fsverity keyctl openssl /etc/ssl/openssl.cnf nano fio" \
	--include "$FSTESTS_SRC $FSTESTS_SRC" \
	--kmods "zram lzo lzo_rle dm_snapshot dm_flakey btrfs raid6_pq \
		 loop scsi_debug dm_log_writes xxhash_generic ext4 virtio_blk"
