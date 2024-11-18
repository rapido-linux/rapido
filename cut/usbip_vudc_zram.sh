#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2024, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args "$RAPIDO_DIR/autorun/usbip_vudc_zram.sh" "$@"
_rt_require_networking
_rt_human_size_in_b "${FSTESTS_ZRAM_SIZE:-1G}" zram_bytes \
	|| _fail "failed to calculate memory resources"
_rt_mem_resources_set "$((512 + (zram_bytes / 1048576)))M"
_rt_require_conf_dir KERNEL_SRC
usbipd_bin="${KERNEL_SRC}/tools/usb/usbip/src/.libs/usbipd"
[[ -x $usbipd_bin ]] \
	|| _fail "usbipd binary missing at $usbipd_bin - needs to be compiled?"

"$DRACUT" --install "tail blockdev ps rmdir resize dd grep find df sha256sum \
		   strace mkfs mkfs.xfs free \
		   ${KERNEL_SRC}/tools/usb/usbip/libsrc/.libs/libusbip.so.0 \
		   ${usbipd_bin}" \
	--add-drivers "usbip-vudc xfs zram lzo lzo-rle" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"
