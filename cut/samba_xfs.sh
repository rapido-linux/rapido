#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2017-2023, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args "$RAPIDO_DIR/autorun/lib/samba.sh" \
			"$RAPIDO_DIR/autorun/samba_xfs.sh" "$@"
_rt_require_networking
req_inst=()
_rt_require_samba_srv req_inst
_rt_human_size_in_b "${FSTESTS_ZRAM_SIZE:-1G}" zram_bytes \
	|| _fail "failed to calculate memory resources"
_rt_mem_resources_set "$((1024 + (zram_bytes / 1048576)))M"
_rt_require_conf_setting CIFS_USER CIFS_PW CIFS_SHARE

"$DRACUT" --install "tail ps rmdir resize dd vim grep find df sha256sum \
		   strace mkfs mkfs.xfs awk dirname \
		   stat which touch cut chmod true false \
		   getfattr setfattr getfacl setfacl killall sync \
		   id sort uniq date expr tac diff head dirname seq \
		   ${req_inst[*]}" \
	--add-drivers "zram lzo xfs lzo-rle" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"
