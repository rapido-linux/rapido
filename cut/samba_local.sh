#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2017-2023, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args "$RAPIDO_DIR/autorun/lib/samba.sh" \
			"$RAPIDO_DIR/autorun/samba_local.sh" "$@"
_rt_require_networking
req_inst=()
_rt_require_samba_srv req_inst "vfs/btrfs.so"
# assign more memory
_rt_mem_resources_set "1024M"

"$DRACUT" --install "tail ps rmdir resize dd vim grep find df sha256sum \
		   strace mkfs mkfs.btrfs awk dirname \
		   stat which touch cut chmod true false \
		   getfattr setfattr getfacl setfacl killall sync \
		   id sort uniq date expr tac diff head dirname seq \
		   ${req_inst[*]}" \
	--add-drivers "zram lzo btrfs lzo-rle" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"
