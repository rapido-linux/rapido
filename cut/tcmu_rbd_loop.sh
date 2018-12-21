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
_rt_require_lib "libkeyutils.so.1 libhandle.so.1 libssl.so.1 libnl-genl-3.so \
  libgio-2.0.so libcryptopp-5.6.2.so.0 libboost_thread.so.1.54.0 libboost_system.so.1.54.0 \
  libboost_random.so.1.54.0 libboost_iostreams.so.1.54.0"

[ -n "$TCMU_RUNNER_SRC" ] || _fail "TCMU_RUNNER_SRC needs to be configured"
tcmu_so_inc=""
for i in `find ${TCMU_RUNNER_SRC} -type f|grep "\.so"`; do
	tcmu_so_inc="${tcmu_so_inc} --include $i /lib64/`basename $i`"
done

"$DRACUT" --install "tail blockdev ps rmdir resize dd vim grep find df sha256sum \
		   strace mkfs.xfs mkfs.btrfs sync dirname uuidgen sleep \
		   $LIBS_INSTALL_LIST" \
	--include "${RAPIDO_DIR}/autorun/tcmu_rbd.sh" "/.profile" \
	--include "${RAPIDO_DIR}/rapido.conf" "/rapido.conf" \
	--include "${RAPIDO_DIR}/vm_autorun.env" "/vm_autorun.env" \
	--include "$CEPH_RADOS_LIB" "/lib64/librados.so" \
	--include "$CEPH_RBD_LIB" "/lib64/librbd.so" \
	--include "$CEPH_CONF" "/etc/ceph/ceph.conf" \
	--include "$CEPH_KEYRING" "/etc/ceph/keyring" \
	--include "${TCMU_RUNNER_SRC}/tcmu-runner" "/bin/tcmu-runner" \
	$tcmu_so_inc \
	--add-drivers "target_core_mod target_core_user tcm_loop" \
	--modules "bash base network ifcfg" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT
