#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2019-2023, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

vm_ceph_conf="$(mktemp --tmpdir vm_ceph_conf.XXXXX)"
# remove tmp file once we're done
trap "rm $vm_ceph_conf" 0

_rt_require_dracut_args "$vm_ceph_conf" "$RAPIDO_DIR/autorun/lib/samba.sh" \
			"$RAPIDO_DIR/autorun/samba_kernel_cephfs.sh" "$@"
_rt_require_networking
_rt_require_ceph
_rt_write_ceph_config "$vm_ceph_conf"
req_inst=()
_rt_require_samba_srv req_inst
# assign more memory
_rt_mem_resources_set "1024M"
_rt_require_conf_setting CIFS_USER CIFS_PW CIFS_SHARE

"$DRACUT" --install "tail ps rmdir resize dd vim grep find df sha256sum \
		   strace stat which touch cut chmod true false \
		   getfattr setfattr getfacl setfacl killall sync \
		   id sort uniq date expr tac diff head dirname seq \
		   ${req_inst[*]}" \
	--add-drivers "ceph libceph" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"
