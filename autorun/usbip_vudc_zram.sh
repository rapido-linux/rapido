#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2024, all rights reserved.

modprobe -a configfs zram xfs usbip-vudc
_vm_ar_dyn_debug_enable
_vm_ar_configfs_mount

export PATH="${KERNEL_SRC}/tools/usb/usbip/src/.libs/:${PATH}"
export LD_LIBRARY_PATH="${KERNEL_SRC}/tools/usb/usbip/libsrc/.libs/"

set -x
mkdir -p /mnt
echo "${FSTESTS_ZRAM_SIZE:-1G}" > /sys/devices/virtual/block/zram0/disksize \
	|| _fatal
mkfs.xfs /dev/zram0 || _fatal
mount /dev/zram0 /mnt/ || _fatal
echo "hello from usbip server" > /mnt/data || _fatal
umount /mnt/ || _fatal

mkdir -p /sys/kernel/config/usb_gadget/confs/strings/0x409 \
	/sys/kernel/config/usb_gadget/confs/functions/mass_storage.usb0 \
	/sys/kernel/config/usb_gadget/confs/configs/c.1/strings/0x409
cd /sys/kernel/config/usb_gadget/confs || _fatal
echo 0x1d6b > idVendor # Linux Foundation
echo 0x0104 > idProduct # Multifunction Composite Gadget
echo 0x0090 > bcdDevice # v0.9.0

echo "openSUSE" > strings/0x409/manufacturer
echo "rapido" > strings/0x409/product

echo 1 > functions/mass_storage.usb0/stall || _fatal
echo 0 > functions/mass_storage.usb0/lun.0/cdrom || _fatal
echo 0 > functions/mass_storage.usb0/lun.0/ro || _fatal
echo 0 > functions/mass_storage.usb0/lun.0/nofua || _fatal
echo 1 > functions/mass_storage.usb0/lun.0/removable || _fatal
echo /dev/zram0 > functions/mass_storage.usb0/lun.0/file || _fatal

echo "Config 1: mass-storage" > configs/c.1/strings/0x409/configuration || _fatal
echo 500 > configs/c.1/MaxPower
ln -s functions/mass_storage.usb0 configs/c.1/ || _fatal

echo "UDC: $(ls /sys/class/udc)"
ls /sys/class/udc > UDC || _fatal

setsid --fork usbipd --device

set +x
