#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2018, all rights reserved.
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

_rt_require_dracut_args "${RAPIDO_DIR}/autorun/lio_pscsi_loop.sh"

# the pscsi VM should be booted with a virtio SCSI device attached. E.g.
# QEMU_EXTRA_ARGS="-nographic -device virtio-scsi-pci,id=scsi \
#   -drive if=none,id=hda,file=/dev/zram0,cache=none,format=raw,serial=RAPIDO \
#   -device scsi-hd,drive=hda"

"$DRACUT" --install "tail blockdev ps rmdir resize dd vim grep find df sha256sum \
		   mkfs mkfs.xfs parted partprobe sgdisk hdparm uuidgen \
		   env lsscsi awk" \
	$DRACUT_RAPIDO_INCLUDES \
	--add-drivers "virtio_scsi target_core_pscsi tcm_loop" \
	--modules "bash base" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT || _fail "dracut failed"

_rt_xattr_vm_networkless_set "$DRACUT_OUT"

