#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LINUX GmbH 2016, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

vm_ceph_conf="$(mktemp --tmpdir vm_ceph_conf.XXXXX)"
# remove tmp file once we're done
trap "rm $vm_ceph_conf" 0

_rt_require_dracut_args "$vm_ceph_conf" "$RAPIDO_DIR/autorun/cephfs_fuse.sh" \
			"$@"
_rt_require_networking
_rt_require_ceph
_rt_write_ceph_config $vm_ceph_conf
_rt_write_ceph_bin_paths $vm_ceph_conf
req_inst=()
_rt_require_lib req_inst "libsoftokn3.so \
		 libfreeblpriv3.so"	# NSS_InitContext() fails without

"$DRACUT" --install "tail ps rmdir resize dd vim grep find df sha256sum \
		   strace stat truncate touch cut chmod getfattr setfattr \
		   getfacl setfacl killall sync dirname seq \
		   $CEPH_FUSE_BIN \
		   ${req_inst[*]}" \
	--include "$CEPH_CONF" "/etc/ceph/ceph.conf" \
	--include "$CEPH_KEYRING" "/etc/ceph/keyring" \
	--add-drivers "fuse" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT"
