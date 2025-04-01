#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2025, all rights reserved.

_vm_ar_env_check || exit 1

set -x

modprobe fuse
_vm_ar_dyn_debug_enable

set +x

# USER used for net-setup.sh TAP_USER
export USER=root
cd "${LKL_SRC}/tools/lkl/tests"

cat <<EOF
Ready for LKL testing.

E.g. to run all tests:
  find . -type f -executable -name '*.sh' -exec '{}' ';'
EOF
