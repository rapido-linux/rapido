#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2025, all rights reserved.

_vm_ar_env_check || exit 1

set -x

modprobe fuse
_vm_ar_dyn_debug_enable

set +x

# Dracut mounts /dev/shm with noexec. drop it for arch/lkl/mm/mmu_mem.c
# mmap_pages_for_ptes() which calls shmem_mmap() with PROT_EXEC:
# https://github.com/lkl/linux/issues/606
mount -t tmpfs -o remount,mode=1777,nosuid,nodev,strictatime tmpfs /dev/shm

# USER used for net-setup.sh TAP_USER
export USER=root
cd "${LKL_SRC}/tools/lkl/tests"

cat <<EOF
Ready for LKL testing.

E.g. to run all tests:
  find . -type f -executable -name '*.sh' -exec '{}' ';'
EOF
