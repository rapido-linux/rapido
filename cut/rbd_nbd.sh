#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2018, all rights reserved.
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
_rt_require_lib "libsoftokn3.so libsqlite3.so \
		 libfreeblpriv3.so"	# NSS_InitContext() fails without

# only support recent (cmake) source based builds for now
[ -n "$CEPH_SRC" ] || _fail "$0 requires CEPH_SRC config"
rbd_nbd_bin="${CEPH_SRC}/build/bin/rbd-nbd"
[ -x "$rbd_nbd_bin" ] || _fail "rbd-nbd executable missing at $rbd_nbd_bin"

"$DRACUT" --install "tail blockdev ps rmdir resize dd vim grep find df sha256sum \
		   strace mkfs.xfs mkfs.btrfs sync dirname uuidgen sleep \
		   $LIBS_INSTALL_LIST $rbd_nbd_bin" \
	--include "${RAPIDO_DIR}/autorun/rbd_nbd.sh" "/.profile" \
	--include "${RAPIDO_DIR}/rapido.conf" "/rapido.conf" \
	--include "${RAPIDO_DIR}/vm_autorun.env" "/vm_autorun.env" \
	--include "$CEPH_CONF" "/etc/ceph/ceph.conf" \
	--include "$CEPH_KEYRING" "/etc/ceph/keyring" \
	--add-drivers "nbd" \
	--modules "bash base network ifcfg" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT
