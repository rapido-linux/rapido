#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2016-2019, all rights reserved.
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

_rt_require_dracut_args
_rt_require_conf_dir TCMU_RUNNER_SRC

"$DRACUT" --install "tail blockdev ps rmdir resize dd vim grep find df sha256sum \
		   strace mkfs.xfs mkfs.btrfs sync dirname uuidgen ip ping \
		   ${TCMU_RUNNER_SRC}/tcmu-runner \
		   ${TCMU_RUNNER_SRC}/handler_file_zbc.so \
		   $LIBS_INSTALL_LIST" \
	--include "${RAPIDO_DIR}/autorun/tcmu_zbc_loop.sh" "/.profile" \
	--include "${RAPIDO_DIR}/rapido.conf" "/rapido.conf" \
	--include "${RAPIDO_DIR}/vm_autorun.env" "/vm_autorun.env" \
	--add-drivers "target_core_mod target_core_user tcm_loop" \
	--modules "bash base" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT || _fail "dracut failed"

_rt_xattr_vm_networkless_set "$DRACUT_OUT"
