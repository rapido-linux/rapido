#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2022, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args "${RAPIDO_DIR}/autorun/lib/ublksrv.sh" \
			"${RAPIDO_DIR}/autorun/ublksrv_zram.sh" "$@"
_rt_mem_resources_set "1024M"

_rt_require_conf_dir UBLKSRV_SRC
# if liburing is set then pull in SOs, let Dracut grab system lib if not
[ -n "$LIBURING_SRC" ] && liburing_libs="${LIBURING_SRC}/src/liburing.so.*"

"$DRACUT" --install "tail ps rmdir resize dd find df strace sync mkfs.xfs \
		$liburing_libs ${UBLKSRV_SRC}/.libs/ublk
		${UBLKSRV_SRC}/lib/.libs/libublksrv.so.*" \
	--add-drivers "ublk_drv xfs zram lzo lzo-rle" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"
