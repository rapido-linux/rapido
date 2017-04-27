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

KVER="`cat ${KERNEL_SRC}/include/config/kernel.release`" || exit 1
dracut --no-compress  --kver "$KVER" \
	--install "tail blockdev ps rmdir resize dd vim grep find df sha256sum \
		   strace mkfs mkfs.xfs /lib64/libkeyutils.so.1 \
		   which perl awk bc touch cut chmod true false \
		   fio getfattr setfattr chacl attr killall sync \
		   id sort uniq date expr tac diff head dirname seq \
		   /usr/lib64/libhandle.so.1 /lib64/libssl.so.1.0.0" \
	--include "$CEPH_MOUNT_BIN" "/sbin/mount.ceph" \
	--include "$CEPH_CONF" "/etc/ceph/ceph.conf" \
	--include "$CEPH_KEYRING" "/etc/ceph/keyring" \
	--include "$RAPIDO_DIR/cephfs_autorun.sh" "/.profile" \
	--include "$RAPIDO_DIR/rapido.conf" "/rapido.conf" \
	--include "$RAPIDO_DIR/vm_autorun.env" "/vm_autorun.env" \
	--no-hostonly --no-hostonly-cmdline \
	--add-drivers "ceph libceph e1000" \
	--modules "bash base network ifcfg" \
	--tmpdir "$RAPIDO_DIR/initrds/" \
	--force $DRACUT_OUT
