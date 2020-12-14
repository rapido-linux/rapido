#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2016, all rights reserved.
#
# This library is free software; you can redistribute it and/or modify it
# under the terms of the GNU Lesser General Public License as published
# by the Free Software Foundation; either version 2.1 of the License, or
# (at your option) version 3.
#
# This library is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
# License for more details.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args
_rt_require_ceph
_rt_require_lib "libkeyutils.so.1"

"$DRACUT" --install "tail blockdev ps rmdir resize dd vim grep find df sha256sum \
		   strace mkfs.xfs lsscsi \
		   $LIBS_INSTALL_LIST" \
	$DRACUT_RAPIDO_INCLUDES \
	--modules "$DRACUT_RAPIDO_MODULES" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT || _fail "dracut failed"

# set qemu arguments to attach the RBD image. qemu uses librbd, and supports
# writeback caching via a "cache=writeback" parameter.
qemu_cut_args="-drive format=rbd,file=rbd:${CEPH_RBD_POOL}/${CEPH_RBD_IMAGE}"
qemu_cut_args="${qemu_cut_args}:conf=${CEPH_CONF},if=virtio,cache=none,format=raw"
_rt_xattr_qemu_args_set "$DRACUT_OUT"  "$qemu_cut_args"
_rt_xattr_vm_networkless_set "$DRACUT_OUT"
