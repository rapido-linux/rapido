#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2022, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args "$RAPIDO_DIR/autorun/simple_network.sh" "$@"

"$DRACUT" \
	--install "nc hostname ip ping" \
	$DRACUT_RAPIDO_INCLUDES \
	--modules "base" \
	$DRACUT_EXTRA_ARGS \
	"$DRACUT_OUT" || _fail "dracut failed"

_rt_xattr_vm_resources_set "$DRACUT_OUT" "1" "512M"
