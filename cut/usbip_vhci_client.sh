#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2024, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args "$RAPIDO_DIR/autorun/usbip_vhci_client.sh" "$@"
_rt_require_networking
_rt_require_conf_dir KERNEL_SRC
usbip_bin="${KERNEL_SRC}/tools/usb/usbip/src/.libs/usbip"
[[ -x $usbip_bin ]] \
	|| _fail "usbip binary missing at $usbip_bin - needs to be compiled?"

"$DRACUT" --install "tail blockdev ps rmdir resize dd grep find df sha256sum \
		   strace mkfs mkfs.xfs free \
		   ${KERNEL_SRC}/tools/usb/usbip/libsrc/.libs/libusbip.so.0 \
		   ${usbip_bin}" \
	--add-drivers "vhci-hcd usb-storage xfs" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"

