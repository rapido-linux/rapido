#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2024, all rights reserved.

modprobe -a usbip-host usb-storage xhci-hcd xhci-pci
_vm_ar_dyn_debug_enable

export PATH="${KERNEL_SRC}/tools/usb/usbip/src/.libs/:${PATH}"
export LD_LIBRARY_PATH="${KERNEL_SRC}/tools/usb/usbip/libsrc/.libs/"

set -x
setsid --fork usbipd
set +x

cat <<EOF
Ready to export local devices to a USBIP client, e.g.:
# usbip list -l
# usbip bind --busid 1-2
# ...
# usbip unbind --busid 1-2
EOF
