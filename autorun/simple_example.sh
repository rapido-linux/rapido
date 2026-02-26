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

echo "Rapido scratch VM running. Have a lot of fun..."
# end of *test* script.

# returning here will drop into the Dracut shell prompt.
# "shutdown" can be called to shutdown the VM (see vm_autorun.env alias).
