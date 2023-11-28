#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)

# The tn40xx-test directory and test scripts will be copied
# by the cut script, from the tn40xx-driver source,
# as defined in the rapido.conf file.

_vm_ar_env_check || exit 1
_vm_ar_dyn_debug_enable

ip link set lo up

/driver-tests/start.sh ${NET_TEST_DEV_VM} ${NET_TEST_KMOD}
