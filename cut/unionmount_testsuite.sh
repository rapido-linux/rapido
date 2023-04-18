#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2021, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args "$RAPIDO_DIR/autorun/unionmount_testsuite.sh" "$@"
_rt_require_conf_dir UNIONMOUNT_TESTSUITE_SRC
_rt_mem_resources_set "4096M"

# this pulls in all local python libraries, which may be very large
py_inc=($(python3 -c \
	  "import sys, os; \
	   [print('--include', p, p) for p in sys.path if os.path.exists(p)]" \
	)) || _fail "failed to determine PYTHON_PATH"

"$DRACUT" --install "tail blockdev ps rmdir resize dd vim grep find df sha256sum \
		   strace mkfs.xfs mkfs.btrfs python3" \
	--include "$UNIONMOUNT_TESTSUITE_SRC" "$UNIONMOUNT_TESTSUITE_SRC" \
	"${py_inc[@]}" \
	--add-drivers "zram lzo lzo-rle btrfs raid6_pq overlay" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"
