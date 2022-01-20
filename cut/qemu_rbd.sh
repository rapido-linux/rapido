#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2016-2022, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

qemu_args_file="$(mktemp --tmpdir rbd_qemu_args.XXXXX)"
trap "rm $qemu_args_file" 0 1 2 3 15

_rt_require_dracut_args
_rt_require_ceph
_rt_require_lib "libkeyutils.so.1"

cat >"$qemu_args_file" <<EOF
-drive format=rbd,file=rbd:${CEPH_RBD_POOL}/${CEPH_RBD_IMAGE}:conf=${CEPH_CONF},if=virtio,cache=none,format=raw
EOF
# set qemu arguments to attach the RBD image. qemu uses librbd, and supports
# writeback caching via a "cache=writeback" parameter.
_rt_qemu_custom_args_set "$qemu_args_file"

"$DRACUT" --install "tail blockdev ps rmdir resize dd vim grep find df sha256sum \
		   strace mkfs.xfs lsscsi \
		   $LIBS_INSTALL_LIST" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"
