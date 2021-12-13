#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2018-2021, all rights reserved.

_vm_ar_env_check || exit 1
_vm_ar_dyn_debug_enable

set -x
fio --name=verify-rd --rw=read --size=1M --verify=crc32c --filename=/fiod \
	|| _fatal
set +x
echo "fio data verification successful"
