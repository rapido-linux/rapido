#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2018, all rights reserved.
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

_rt_require_dracut_args "${RAPIDO_DIR}/autorun/openiscsi.sh" "$@"
_rt_require_conf_dir OPENISCSI_SRC

"$DRACUT" \
	--install "grep ps dd mkfs.xfs ip ping \
		   ${OPENISCSI_SRC}/usr/iscsid \
		   ${OPENISCSI_SRC}/libopeniscsiusr/libopeniscsiusr.so \
		   ${OPENISCSI_SRC}/usr/iscsiadm" \
	$DRACUT_RAPIDO_INCLUDES \
	--modules "bash base" \
	--drivers "iscsi_tcp" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT || _fail "dracut failed"
