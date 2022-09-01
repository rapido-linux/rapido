#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2022, all rights reserved.

_vm_ar_env_check || exit 1

set -x

modprobe ublk_drv || _fatal "failed to load ublk_drv kernel module"
_vm_ar_dyn_debug_enable
_ublksrv_env_init

ublk add -t null || _fatal "failed to add ublk device"
ublk list

set +x
