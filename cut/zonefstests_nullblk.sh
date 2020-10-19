#!/bin/bash
#
# Copyright (C) 2020 Western Digital Corporation, all rights reserved.
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

_rt_require_dracut_args "$RAPIDO_DIR/autorun/zonefstests_nullblk.sh"
_rt_require_conf_dir ZONEFSTOOLS_SRC

"$DRACUT" --install "$DRACUT_RAPIDO_INSTALL \
		ps rmdir dd id basename stat wc grep blkzone cut fio \
		rm truncate ${ZONEFSTOOLS_SRC}/src/mkzonefs" \
	--include "$ZONEFSTOOLS_SRC/tests/" "/zonefs-tests" \
	$DRACUT_RAPIDO_INCLUDES \
	--add-drivers "null_blk zonefs" \
	--modules "bash base" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT || _fail "dracut failed"

_rt_xattr_vm_networkless_set "$DRACUT_OUT"

_rt_xattr_vm_resources_set "$DRACUT_OUT" "2" "2048M"
