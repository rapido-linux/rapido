#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE S.A. 2018-2026, all rights reserved.

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

mapfile -n 3 -d ' ' kver < /proc/version
echo "Rapido scratch VM running ${kver[2]/ }. Have a lot of fun..."

# returning will run any subsequent autorun script, or drop into an interactive
# shell. "shutdown" or "exit" can be invoked to shutdown the VM.
