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

_rt_require_dracut_args
_rt_require_conf_dir SAMBA_SRC

"$DRACUT" --install "tail ps rmdir resize dd vim grep find df sha256sum \
		   strace mkfs mkfs.btrfs mkfs.xfs \
		   stat which touch cut chmod true false \
		   getfattr setfattr chacl attr killall sync \
		   id sort uniq date expr tac diff head dirname seq ip ping \
		   ${SAMBA_SRC}/bin/smbpasswd \
		   ${SAMBA_SRC}/bin/modules/vfs/btrfs.so \
		   ${SAMBA_SRC}/bin/smbd" \
	--include "$RAPIDO_DIR/autorun/samba_local.sh" "/.profile" \
	--include "$RAPIDO_DIR/rapido.conf" "/rapido.conf" \
	--include "$RAPIDO_DIR/vm_autorun.env" "/vm_autorun.env" \
	--add-drivers "zram lzo lzo-rle xfs btrfs" \
	--modules "bash base" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT || _fail "dracut failed"

# assign more memory
_rt_xattr_vm_resources_set "$DRACUT_OUT" "2" "1024M"
