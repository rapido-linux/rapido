#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2024, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args "$RAPIDO_DIR/autorun/sys_param_check.sh" "$@"
_rt_require_conf_dir SYS_PARAM_CHECK_SRC
_rt_mem_resources_set "4096M"
req_inst=()
# libexpat needed for python 'import xml.parsers.expat'
_rt_require_lib req_inst "libexpat.so.1"
_rt_require_pam_mods req_inst "pam_rootok.so" "pam_limits.so"

# this pulls in all local python libraries, which may be very large
py_inc=($(python3 -c \
	  "import sys, os; \
	   [print('--include', p, p) for p in sys.path if os.path.exists(p)]" \
	)) || _fail "failed to determine PYTHON_PATH"

# systemd boot used as it sets some sysctl limits (e.g. core size)
"$DRACUT" --install "tail blockdev ps rmdir resize dd grep find df \
		   python3 robot su useradd sysctl ${req_inst[*]}" \
	--include "$SYS_PARAM_CHECK_SRC" "$SYS_PARAM_CHECK_SRC" \
	"${py_inc[@]}" \
	--modules "base dracut-systemd" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"
