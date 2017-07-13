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

RAPIDO_DIR="$(realpath -e ${0%/*})"
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_ceph
_rt_require_dracut_args
_rt_require_lib "libkeyutils.so.1 libfuse.so libcryptopp-5.6.2.so.0 libhandle.so.1 libssl.so.1"

"$DRACUT" --install "tail blockdev ps rmdir resize dd vim grep find df sha256sum \
		   strace mkfs mkfs.xfs \
		   which perl awk bc touch cut chmod true false \
		   fio getfattr setfattr chacl attr killall sync \
		   id sort uniq date expr tac diff head dirname seq \
		   $LIBS_INSTALL_LIST" \
	--include "$CEPH_FUSE_BIN" "/bin/ceph-fuse" \
	--include "$CEPH_CONF" "/etc/ceph/ceph.conf" \
	--include "$CEPH_KEYRING" "/etc/ceph/keyring" \
	--include "$RAPIDO_DIR/cephfs_fuse_autorun.sh" "/.profile" \
	--include "$RAPIDO_DIR/rapido.conf" "/rapido.conf" \
	--include "$RAPIDO_DIR/vm_autorun.env" "/vm_autorun.env" \
	--add-drivers "fuse" \
	--modules "bash base network ifcfg" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT
