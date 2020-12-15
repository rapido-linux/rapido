#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2017, all rights reserved.
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

_rt_require_dracut_args "$RAPIDO_DIR/autorun/mpath_local.sh" "$@"

# the VM should be deployed with two virtio SCSI devices which share the same
# backing <file> and <serial> parameters. E.g.
#QEMU_EXTRA_ARGS="-nographic -device virtio-scsi-pci,id=scsi \
#    -drive if=none,id=hda,file=/dev/zram4,cache=none,format=raw,serial=RAPIDO \
#    -device scsi-hd,drive=hda \
#    -drive if=none,id=hdb,file=/dev/zram4,cache=none,format=raw,serial=RAPIDO \
#    -device scsi-hd,drive=hdb"
#
# Once booted, you can simulate path failure by switching to the QEMU console
# (ctrl-a c) and running "drive_del hda"

"$DRACUT" --install "$DRACUT_RAPIDO_INSTALLS \
		tail blockdev ps rmdir resize dd vim grep find df sha256sum \
		strace mkfs mkfs.xfs parted partprobe sgdisk hdparm \
		timeout id chown chmod env killall getopt basename" \
	$DRACUT_RAPIDO_INCLUDES \
	--add-drivers "virtio_scsi virtio_pci sd_mod" \
	--modules "$DRACUT_RAPIDO_MODULES systemd systemd-initrd dracut-systemd multipath" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT \
	|| _fail "dracut failed"

_rt_xattr_vm_networkless_set "$DRACUT_OUT"
