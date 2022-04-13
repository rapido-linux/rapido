#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2022, all rights reserved.

_vm_ar_env_check || exit 1
_vm_ar_dyn_debug_enable

ip addr
cat <<EOF
Rapido simple network VM running. Usage examples:

# Listen on port 54912...
nc -ln 54912

# connect to 192.168.155.101:54912 and say hello
echo "hello!" | nc 192.168.155.101 54912

Have a lot of fun...
EOF
