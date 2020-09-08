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

_rt_require_ceph
_rt_require_dracut_args
_rt_require_lib "libkeyutils.so.1"

"$DRACUT" --install "tail blockdev ps rmdir resize dd vim grep find df sha256sum \
		   eject strace mkfs.vfat mountpoint \
		   mktemp touch sync cryptsetup dmsetup scp ssh ip ping \
		   /usr/lib/udev/rules.d/10-dm.rules \
		   /usr/lib/udev/rules.d/13-dm-disk.rules \
		   /usr/lib/udev/rules.d/95-dm-notify.rules \
		   $LIBS_INSTALL_LIST" \
	--include "$CEPH_CONF" "/etc/ceph/ceph.conf" \
	--include "$CEPH_KEYRING" "/etc/ceph/keyring" \
	--include "$RBD_NAMER_BIN" "/usr/bin/ceph-rbdnamer" \
	--include "$RBD_UDEV_RULES" "/usr/lib/udev/rules.d/50-rbd.rules" \
	--include "$RAPIDO_DIR/autorun/usb_rbd.sh" "/.profile" \
	--include "$RBD_USB_SRC/rbd-usb.sh" "/bin/rbd-usb.sh" \
	--include "$RBD_USB_SRC/conf-fs.sh" "/bin/conf-fs.sh" \
	--include "$RBD_USB_SRC/rbd-usb.env" "/usr/lib/rbd-usb.env" \
	--include "$RBD_USB_SRC/rbd-usb.conf" "/etc/rbd-usb/rbd-usb.conf" \
	$DRACUT_RAPIDO_INCLUDES \
	--add-drivers "target_core_mod target_core_iblock usb_f_tcm \
		       usb_f_mass_storage zram lzo lzo-rle dm-crypt" \
	--modules "bash base" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT
