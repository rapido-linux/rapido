#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2022, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args "$RAPIDO_DIR/autorun/nfs_client.sh" "$@"
_rt_require_networking

"$DRACUT" --install "tail ps rmdir resize dd vim grep find df du truncate \
		   strace mount.nfs rpcbind rpcinfo rpc.statd sm-notify \
		   touch chmod getfacl setfacl getfattr setfattr killall sync \
		   dirname seq basename chattr lsattr stat" \
	--add-drivers "nfs nfsv3 nfsv4" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"
