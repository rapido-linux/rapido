#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2019-2022, all rights reserved.

_vm_ar_env_check || exit 1

_vm_ar_dyn_debug_enable

set -x

# ltp requires a few preexisting users/groups
xid="2000"
for ug in nobody bin daemon; do
	echo "${ug}:x:${xid}:${xid}:${ug} user:/:/sbin/nologin" >> /etc/passwd
	echo "${ug}:x:${xid}:" >> /etc/group
	((xid++))
done

export CREATE_ENTRIES=0
export KCONFIG_PATH=/.config
export LTPROOT="$LTP_DIR"
export PATH="$LTP_DIR:$LTP_DIR/bin:$LTP_DIR/testcases/bin:$PATH"

cd $LTP_DIR/testcases/bin/ || _fatal
if [ -n "$LTP_AUTORUN_CMD" ]; then
	echo "Running LTP Command: $LTP_AUTORUN_CMD"
	eval "$LTP_AUTORUN_CMD"
fi

# LTP net tests need loopback networking
ip link set dev lo up
