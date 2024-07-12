#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LINUX GmbH 2018, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

vm_ceph_conf="$(mktemp --tmpdir vm_ceph_conf.XXXXX)"
# remove tmp file once we're done
trap "rm $vm_ceph_conf" 0

_rt_require_dracut_args "$vm_ceph_conf" "${RAPIDO_DIR}/autorun/rbd_nbd.sh" "$@"
_rt_require_networking
_rt_require_ceph
_rt_write_ceph_config $vm_ceph_conf
req_inst=()
_rt_require_lib req_inst "libsoftokn3.so libsqlite3.so \
		 libfreeblpriv3.so"	# NSS_InitContext() fails without

# only support recent (cmake) source based builds for now
[ -n "$CEPH_SRC" ] || _fail "$0 requires CEPH_SRC config"
rbd_nbd_bin="${CEPH_SRC}/build/bin/rbd-nbd"
[ -x "$rbd_nbd_bin" ] || _fail "rbd-nbd executable missing at $rbd_nbd_bin"

"$DRACUT" --install "tail blockdev ps rmdir resize dd vim grep find df sha256sum \
		   strace mkfs.xfs mkfs.btrfs sync dirname uuidgen sleep \
		   ${req_inst[*]} $rbd_nbd_bin" \
	--include "$CEPH_CONF" "/etc/ceph/ceph.conf" \
	--include "$CEPH_KEYRING" "/etc/ceph/keyring" \
	--add-drivers "nbd" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT"
