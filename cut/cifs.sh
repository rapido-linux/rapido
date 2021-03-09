#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2019, all rights reserved.
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

_rt_require_dracut_args "$RAPIDO_DIR/autorun/cifs.sh" "$@"

"$DRACUT" --install "tail ps rmdir resize dd vim grep find df \
		   mount.cifs ip ping getfacl setfacl truncate du \
		   which touch cut chmod true false unlink \
		   getfattr setfattr chacl attr killall sync \
		   dirname seq basename fstrim chattr lsattr stat" \
	$DRACUT_RAPIDO_INCLUDES \
	--add-drivers "cifs ccm gcm ctr" \
	--modules "base" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT || _fail "dracut failed"
