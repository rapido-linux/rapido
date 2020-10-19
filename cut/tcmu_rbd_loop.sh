#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2016-2019, all rights reserved.
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

_rt_require_dracut_args "${RAPIDO_DIR}/autorun/tcmu_rbd_loop.sh"
_rt_require_conf_dir TCMU_RUNNER_SRC CEPH_SRC
_rt_require_ceph
# NSS_InitContext() fails without the following...
_rt_require_lib "libsoftokn3.so libfreeblpriv3.so"

"$DRACUT" --install "$DRACUT_RAPIDO_INSTALL \
		tail blockdev ps rmdir resize dd vim grep find df sha256sum \
		strace mkfs.xfs mkfs.btrfs sync dirname uuidgen ip ping \
		${CEPH_SRC}/build/lib/librbd.so \
		${CEPH_SRC}/build/lib/libceph-common.so \
		${CEPH_SRC}/build/lib/librados.so \
		${TCMU_RUNNER_SRC}/tcmu-runner \
		${TCMU_RUNNER_SRC}/handler_rbd.so \
		$LIBS_INSTALL_LIST" \
	--include "$CEPH_CONF" "/etc/ceph/ceph.conf" \
	--include "$CEPH_KEYRING" "/etc/ceph/keyring" \
	$DRACUT_RAPIDO_INCLUDES \
	--add-drivers "target_core_mod target_core_user tcm_loop" \
	--modules "bash base" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT
