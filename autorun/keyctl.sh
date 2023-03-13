#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2023, all rights reserved.

_vm_ar_env_check || exit 1

set -x

_vm_ar_dyn_debug_enable

k=$(keyctl add user mykey stuff @u) || _fatal "failed to add user key"

setsid --fork keyctl watch "$k"

set +x

cat <<EOF
$k created and watched. Test events via e.g.
# keyctl clear @u
EOF
