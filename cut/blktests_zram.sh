#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2017, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args "$RAPIDO_DIR/autorun/blktests_zram.sh" "$@"
_rt_require_blktests

"$DRACUT" --install "tail blockdev ps rmdir resize dd vim grep find df sha256sum \
		   getopt tput wc column blktrace losetup parted truncate \
		   lsblk strace which awk bc touch cut chmod true false mktemp \
		   killall id sort uniq date expr tac diff head dirname seq \
		   basename tee egrep hexdump sync fio logger cmp stat nproc \
		   xfs_io modinfo blkdiscard realpath timeout nvme" \
	--include "$BLKTESTS_SRC" "$BLKTESTS_SRC" \
	$DRACUT_RAPIDO_INCLUDES \
	--add-drivers "zram lzo lzo-rle scsi_debug null_blk loop nvme nvme-loop" \
	--modules "base" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT || _fail "dracut failed"

_rt_xattr_vm_networkless_set "$DRACUT_OUT"
