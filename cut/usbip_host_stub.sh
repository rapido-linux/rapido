#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2024, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

# export a VM-local USB device via USB IP. The local USB device can be virtual,
# e.g.
# -drive if=none,id=stick,format=raw,file=/path/to/file.img \
# -device nec-usb-xhci,id=xhci                              \
# -device usb-storage,bus=xhci.0,drive=stick

_rt_require_dracut_args "$RAPIDO_DIR/autorun/usbip_host_stub.sh" "$@"
_rt_require_networking
req_inst=()
_rt_require_usbip_progs req_inst

"$DRACUT" --install "tail blockdev ps rmdir resize dd grep find df sha256sum \
		   strace mkfs mkfs.xfs free lsusb ${req_inst[*]}" \
	--add-drivers "usbip-host usb-storage xhci-hcd xhci-pci" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"
