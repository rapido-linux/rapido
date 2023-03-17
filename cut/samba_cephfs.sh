#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2017-2023, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

vm_ceph_conf="$(mktemp --tmpdir vm_ceph_conf.XXXXX)"
# remove tmp file once we're done
trap "rm $vm_ceph_conf" 0 1 2 3 15

_rt_require_dracut_args "$vm_ceph_conf" "$RAPIDO_DIR/autorun/lib/samba.sh" \
			"$RAPIDO_DIR/autorun/samba_cephfs.sh" "$@"
_rt_require_networking
_rt_require_ceph
_rt_write_ceph_config $vm_ceph_conf
req_inst=()
_rt_require_samba_srv req_inst "vfs/ceph.so"
_rt_require_lib req_inst "libssl3.so libsmime3.so libstdc++.so.6 \
		libsoftokn3.so libfreeblpriv3.so"
# assign more memory
_rt_mem_resources_set "1024M"

"$DRACUT" --install "tail ps rmdir resize dd vim grep find df sha256sum \
		   which touch cut chmod true false \
		   getfattr setfattr chacl attr killall sync \
		   id sort uniq date expr tac diff head dirname seq \
		   ${req_inst[*]}" \
	--include "$CEPH_COMMON_LIB" "/usr/lib64/libceph-common.so.0" \
	--include "$CEPHFS_LIB" "/usr/lib64/libcephfs.so.2" \
	--include "$CEPH_RADOS_LIB" "/usr/lib64/librados.so.2" \
	--include "$CEPH_CONF" "/etc/ceph/ceph.conf" \
	--include "$CEPH_KEYRING" "/etc/ceph/keyring" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"
