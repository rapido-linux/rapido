#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2025, all rights reserved.

_vm_ar_env_check || exit 1

set -x

_vm_ar_hosts_create

# XXX lklfuse-mount@.service should be able to use the
# After/Requires=modprobe@fuse.service for /dev/fuse presence, except the mode
# is only changed to 0666 by a 50-udev-default.rules fuse rule, which may be
# processed *after* lklfuse-mount@.service proceeds.
modprobe -a usb-storage xhci-hcd xhci-pci fuse
_vm_ar_dyn_debug_enable

# fuse by default won't allow access to non-mounters, we need to set:
echo user_allow_other >> /etc/fuse3.conf

set +x

# Dracut mounts /dev/shm with noexec. drop it for arch/lkl/mm/mmu_mem.c
mount -t tmpfs -o remount,mode=1777,nosuid,nodev,strictatime tmpfs /dev/shm

systemctl start systemd-udevd
udevadm settle
