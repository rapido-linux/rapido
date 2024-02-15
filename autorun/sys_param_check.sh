#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2024, all rights reserved.

_vm_ar_env_check || exit 1

set -x

_vm_ar_dyn_debug_enable

echo -e "passwd: files\ngroup: files" > /etc/nsswitch.conf

# minimal pam config to allow root to use useradd and su <user>
mkdir -p /etc/pam.d /etc/security
set +x
cat > /etc/pam.d/other <<EOF
auth    sufficient      pam_rootok.so
account sufficient      pam_rootok.so
session required        pam_limits.so
EOF
cat > /etc/security/limits.conf <<EOF
# systemd sets '* soft core unlimited' for us
EOF

cd "$SYS_PARAM_CHECK_SRC"

cat <<EOF
To run a test:
  robot tests/...

E.g. to run a test on boot:
  ./rapido cut -x 'robot tests/...' sys-param-check
EOF
