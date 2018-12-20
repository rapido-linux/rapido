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

_rt_require_dracut_args

"$DRACUT" --install "tail blockdev ps rmdir resize dd vim grep find df sha256sum \
		   strace mkfs.xfs truncate losetup dmsetup \
		   /usr/lib/udev/rules.d/95-dm-notify.rules" \
	--include "$RAPIDO_DIR/autorun/lio_local.sh" "/.profile" \
	--include "$RAPIDO_DIR/rapido.conf" "/rapido.conf" \
	--include "$RAPIDO_DIR/vm_autorun.env" "/vm_autorun.env" \
	--add-drivers "iscsi_target_mod target_core_mod target_core_iblock \
		       target_core_file dm-delay loop" \
	--modules "bash base network ifcfg" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT || _fail "dracut failed"

_rt_xattr_vm_resources_set "$DRACUT_OUT" "2" "2048M"
