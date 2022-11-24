#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2016-2022, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args "$RAPIDO_DIR/autorun/lib/fstests.sh" \
			"$RAPIDO_DIR/autorun/fstests_xfs.sh" "$@"
_rt_require_fstests
_rt_human_size_in_b "${FSTESTS_ZRAM_SIZE:-1G}" zram_bytes \
	|| _fail "failed to calculate memory resources"
# 2x multiplier for one test and one scratch zram. +2G as buffer
_rt_mem_resources_set "$((2048 + (zram_bytes * 2 / 1048576)))M"

"$DRACUT" --install "tail blockdev ps rmdir resize dd vim grep find df sha256sum \
		   strace mkfs mkfs.xfs free ip \
		   which perl awk bc touch cut chmod true false unlink \
		   mktemp getfattr setfattr chacl attr killall hexdump sync \
		   id sort uniq date expr tac diff head dirname seq \
		   basename tee egrep yes \
		   fstrim fio logger dmsetup chattr lsattr cmp stat \
		   dbench /usr/share/dbench/client.txt hostname getconf md5sum \
		   od wc getfacl setfacl tr xargs sysctl link truncate quota \
		   repquota setquota quotacheck quotaon pvremove vgremove \
		   xfs_mkfile xfs_db xfs_io fsck \
		   xfs_mdrestore xfs_bmap xfs_fsr xfsdump xfs_freeze xfs_info \
		   xfs_logprint xfs_repair xfs_growfs xfs_quota xfs_metadump \
		   chgrp du fgrep pgrep tar rev kill duperemove \
		   ${FSTESTS_SRC}/ltp/* ${FSTESTS_SRC}/src/* \
		   ${FSTESTS_SRC}/src/log-writes/* \
		   ${FSTESTS_SRC}/src/aio-dio-regress/*" \
	--include "$FSTESTS_SRC" "$FSTESTS_SRC" \
	--add-drivers "zram lzo lzo-rle dm-snapshot dm-flakey xfs \
		       loop scsi_debug dm-log-writes virtio_blk" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"
