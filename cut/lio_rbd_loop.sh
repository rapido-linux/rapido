#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2023, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

vm_ceph_conf="$(mktemp --tmpdir vm_ceph_conf.XXXXX)"
# remove tmp file once we're done
trap "rm $vm_ceph_conf" 0 1 2 3 15

_rt_require_dracut_args "$vm_ceph_conf" "${RAPIDO_DIR}/autorun/lib/ceph.sh" \
			"${RAPIDO_DIR}/autorun/lio_rbd_loop.sh" "$@"
_rt_require_networking
_rt_require_ceph
_rt_write_ceph_config $vm_ceph_conf

"$DRACUT" --install "tail blockdev ps rmdir resize dd grep find df sha256sum \
		   strace mkfs.xfs uuidgen xxd truncate" \
	--include "$CEPH_CONF" "/etc/ceph/ceph.conf" \
	--include "$CEPH_KEYRING" "/etc/ceph/keyring" \
	--include "$RBD_NAMER_BIN" "/usr/bin/ceph-rbdnamer" \
	--include "$RBD_UDEV_RULES" "/usr/lib/udev/rules.d/50-rbd.rules" \
	--add-drivers "tcm_loop target_core_mod target_core_rbd xfs" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT"
