#!/bin/bash
#
# Copyright (C) SUSE LLC 2020, all rights reserved.
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

_rt_require_dracut_args "${RAPIDO_DIR}/autorun/tcmu_file_iscsi.sh" "$@"
_rt_require_conf_dir TCMU_RUNNER_SRC

"$DRACUT" --install "tail ps rmdir resize dd vim grep find df truncate \
		   strace sync uuidgen ip ping \
		   ${TCMU_RUNNER_SRC}/tcmu-runner \
		   ${TCMU_RUNNER_SRC}/handler_file.so" \
	$DRACUT_RAPIDO_INCLUDES \
	--add-drivers "target_core_mod target_core_user iscsi_target_mod" \
	--modules "base" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT || _fail "dracut failed"

_rt_xattr_vm_resources_set "$DRACUT_OUT" "2" "2048M"
