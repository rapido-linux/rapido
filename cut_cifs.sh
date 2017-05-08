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

_rt_require_dracut_args

dracut  --install "tail blockdev ps rmdir resize dd vim grep find df sha256sum \
		   strace mkfs mkfs.xfs /lib64/libkeyutils.so.1 \
		   which perl awk bc touch cut chmod true false \
		   mktemp getfattr setfattr chacl attr killall \
		   id sort uniq date expr tac diff head dirname seq \
		   /usr/lib64/libhandle.so.1 /lib64/libssl.so.1.0.0 \
		   basename tee egrep hexdump sync xfs_db xfs_io mount.cifs \
		   fstrim fio logger dmsetup chattr cmp stat \
		   dbench /usr/share/dbench/client.txt" \
	--include "$FSTESTS_DIR" "/fstests" \
	--include "$RAPIDO_DIR/cifs_autorun.sh" "/.profile" \
	--include "$RAPIDO_DIR/rapido.conf" "/rapido.conf" \
	--include "$RAPIDO_DIR/vm_autorun.env" "/vm_autorun.env" \
	--add-drivers "cifs" \
	--modules "bash base network ifcfg" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT
