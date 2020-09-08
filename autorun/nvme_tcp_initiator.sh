#!/bin/bash
#
# Copyright (C) SUSE LLC 2019, all rights reserved.
#
# This library is free software; you can redistribute it and/or modify it
# under the terms of the GNU Lesser General Public License as published
# by the Free Software Foundation; either version 2.1 of the License, or
# (at your option) version 3.
#
# This library is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
# License for more details.

_vm_ar_env_check || exit 1

set -x

#### start udevd
ps -eo args | grep -v grep | grep /usr/lib/systemd/systemd-udevd \
	|| /usr/lib/systemd/systemd-udevd --daemon

modprobe configfs
_vm_ar_configfs_mount

modprobe nvme-core
modprobe nvme-fabrics

_vm_ar_dyn_debug_enable

[ -n "$NVME_TARGET_TCP" ] || _fatal "NVME_TARGET_TCP not configured"

nvmet_subsys="nvmf-test"

#nvme connect -t tcp -a "$NVME_TARGET_TCP" -s 11345 -n "$nvmet_subsys" -test || _fatal
echo "transport=tcp,traddr=${NVME_TARGET_TCP},trsvcid=11345,nqn=${nvmet_subsys}" \
	> /dev/nvme-fabrics || _fatal
udevadm settle
nvmedev="$(ls /dev/nvme[0-9]n[0-9])"
set +x
echo "Remote NVMe over TCP $NVME_TARGET_TCP mapped to $nvmedev"
