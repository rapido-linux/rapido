#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2025, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args "$RAPIDO_DIR/autorun/lib/nfs.sh" \
			"$RAPIDO_DIR/autorun/autofs_direct_nfs.sh" "$@"
_rt_require_networking
req_inst=()
_rt_require_autofs req_inst

"$DRACUT" --install "tail ps rmdir resize dd vim grep find df \
		   mount.nfs ip ping getfacl setfacl truncate du \
		   which touch cut chmod true false unlink id \
		   getfattr setfattr chacl attr killall sync strace \
		   dirname seq basename fstrim chattr lsattr stat
		   ${req_inst[*]}" \
	--add-drivers "nfs nfsv3 nfsv4 autofs4" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"
