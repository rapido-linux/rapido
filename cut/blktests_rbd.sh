#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2017, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

vm_ceph_conf="$(mktemp --tmpdir vm_ceph_conf.XXXXX)"
# remove tmp file once we're done
trap "rm $vm_ceph_conf" 0 1 2 3 15

_rt_require_dracut_args "$vm_ceph_conf" "$RAPIDO_DIR/autorun/blktests_rbd.sh" \
			"$@"
_rt_require_ceph
_rt_write_ceph_config $vm_ceph_conf
_rt_require_blktests

"$DRACUT" --install "tail blockdev ps rmdir resize dd vim grep find df sha256sum \
		   getopt tput wc column blktrace losetup parted truncate \
		   lsblk strace which awk bc touch cut chmod true false mktemp \
		   killall id sort uniq date expr tac diff head dirname seq \
		   basename tee egrep hexdump sync fio logger cmp stat nproc \
		   xfs_io modinfo blkdiscard realpath timeout ip ping" \
	--include "$CEPH_CONF" "/etc/ceph/ceph.conf" \
	--include "$CEPH_KEYRING" "/etc/ceph/keyring" \
	--include "$RBD_NAMER_BIN" "/usr/bin/ceph-rbdnamer" \
	--include "$RBD_UDEV_RULES" "/usr/lib/udev/rules.d/50-rbd.rules" \
	--include "$BLKTESTS_SRC" "$BLKTESTS_SRC" \
	$DRACUT_RAPIDO_INCLUDES \
	--add-drivers "scsi_debug null_blk loop" \
	--modules "base" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT
