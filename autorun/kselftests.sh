#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2018-2021, all rights reserved.

# autorun scripts are run once the Rapido scratch VM has booted. The scripts
# are sourced by vm_autorun.env and have access to rapido.conf variables.

# protect against running (harmful) scripts outside of Rapido VMs
_vm_ar_env_check || exit 1

# echo shell commands as they are executed
set -x

# enable dynamic debug for any DYN_DEBUG_MODULES or DYN_DEBUG_FILES specified in
# rapido.conf. All kernel modules *should* be loaded before calling
_vm_ar_dyn_debug_enable

set +x

cd "$KSELFTESTS_DIR"

cat <<EOF
To run a test:
  ./run_kselftest.sh ...

E.g. to run all tests on boot:
  ./rapido cut -x './run_kselftest.sh ...'
EOF
