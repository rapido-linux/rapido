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

_rt_require_dracut_args "${RAPIDO_DIR}/autorun/tgt_local.sh" "$@"
_rt_require_networking
_rt_require_conf_dir TGT_SRC
_rt_mem_resources_set "2048M"

"$DRACUT" \
	--install "grep ps \
		   ${TGT_SRC}/usr/tgtd \
		   ${TGT_SRC}/usr/tgtadm" \
	--add-drivers "zram lzo lzo-rle" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"
