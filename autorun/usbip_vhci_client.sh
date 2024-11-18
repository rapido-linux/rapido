#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2024, all rights reserved.

# kernel documentation refers to usbip/vhci-hcd.ko as usbip-vhci
modprobe -a vhci-hcd xfs
_vm_ar_dyn_debug_enable

export PATH="${KERNEL_SRC}/tools/usb/usbip/src/.libs/:${PATH}"
export LD_LIBRARY_PATH="${KERNEL_SRC}/tools/usb/usbip/libsrc/.libs/"

cat <<EOF
Ready to connect to a USBIP server:
# usbip list -r \$SERVER_IP
# usbip attach -r \$SERVER_IP -d usbip-vudc.0
# ...
# usbip detach -p 0
EOF
