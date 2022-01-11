#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2017, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

vm_ceph_conf="$(mktemp --tmpdir vm_ceph_conf.XXXXX)"
# remove tmp file once we're done
trap "rm $vm_ceph_conf" 0 1 2 3 15

_rt_require_ceph
_rt_write_ceph_config $vm_ceph_conf
_rt_require_dracut_args "$vm_ceph_conf" "${RAPIDO_DIR}/autorun/lib/ceph.sh" \
			"${RAPIDO_DIR}/autorun/nvme_rbd.sh" "$@"
_rt_require_lib "libkeyutils.so.1"

"$DRACUT" --install "tail blockdev ps rmdir resize dd vim grep find df sha256sum \
		   strace mkfs.xfs ip ping \
		   $LIBS_INSTALL_LIST" \
	--include "$CEPH_CONF" "/etc/ceph/ceph.conf" \
	--include "$CEPH_KEYRING" "/etc/ceph/keyring" \
	--include "$RBD_NAMER_BIN" "/usr/bin/ceph-rbdnamer" \
	--include "$RBD_UDEV_RULES" "/usr/lib/udev/rules.d/50-rbd.rules" \
	$DRACUT_RAPIDO_INCLUDES \
	--add-drivers "nvme-core nvme-fabrics nvme-loop nvmet" \
	--modules "base" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT
