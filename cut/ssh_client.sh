#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2022, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args "$RAPIDO_DIR/autorun/ssh_client.sh" "$@"
_rt_require_networking

[ -f "$SSH_KNOWN_HOSTS" ] && \
	known_hosts=("--include" "$SSH_KNOWN_HOSTS" "/etc/ssh/ssh_known_hosts")

"$DRACUT" \
	--install "resize ps rmdir dd ssh /etc/ssh/ssh_config
		   $SSH_IDENTITY ${SSH_IDENTITY}.pub" \
	"${known_hosts[@]}" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"
