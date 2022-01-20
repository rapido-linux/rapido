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

_rt_require_dracut_args "$RAPIDO_DIR/autorun/samba_local.sh" "$@"
_rt_require_networking
_rt_require_conf_dir SAMBA_SRC
# assign more memory
_rt_cpu_resources_set "2"
_rt_mem_resources_set "1024M"

"$DRACUT" --install "tail ps rmdir resize dd vim grep find df sha256sum \
		   strace mkfs mkfs.btrfs mkfs.xfs \
		   stat which touch cut chmod true false \
		   getfattr setfattr getfacl setfacl killall sync \
		   id sort uniq date expr tac diff head dirname seq \
		   ${SAMBA_SRC}/bin/smbpasswd \
		   ${SAMBA_SRC}/bin/smbstatus \
		   ${SAMBA_SRC}/bin/modules/vfs/btrfs.so \
		   ${SAMBA_SRC}/bin/smbd" \
	--add-drivers "zram lzo lzo-rle xfs btrfs" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"
