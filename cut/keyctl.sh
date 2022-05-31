#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2023, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args "$RAPIDO_DIR/autorun/keyctl.sh" "$@"
watch_test_bin="${KERNEL_SRC}/samples/watch_queue/watch_test"
[[ -n $KERNEL_SRC && -x "$watch_test_bin" ]] || watch_test_bin=""

"$DRACUT" \
	--install "$watch_test_bin keyctl strace resize ps rmdir dd" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"
