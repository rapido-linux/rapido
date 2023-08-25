#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2019-2023, all rights reserved

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args "$RAPIDO_DIR/autorun/cifs.sh" "$@"
_rt_require_networking
_rt_require_conf_setting CIFS_SERVER CIFS_SHARE

"$DRACUT" --install "tail ps rmdir resize dd vim grep find df \
		   mount.cifs cifs.upcall getfacl setfacl truncate du \
		   which touch cut chmod true false unlink \
		   getfattr setfattr chacl attr killall sync \
		   dirname seq basename fstrim chattr lsattr stat" \
	--add-drivers "cifs ccm gcm ctr cmac" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"
