#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2018-2021, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

# The job of Rapido cut scripts is to generate a VM image. This is done using
# Dracut with a number of parameters...

# Call _rt_require_dracut_args() providing script paths that will be included
# and run on VM boot. It exports variables used in the dracut invocation below.
_rt_require_dracut_args "$RAPIDO_DIR/autorun/kselftest.sh" "$@"

# _rt_require_networking() flags that VMs using this image should have a network
# adapter. Binaries and configuration required for networking are appended to
# DRACUT_RAPIDO_ARGS.
#_rt_require_networking

# VMs are booted with 2 vCPUs and 512M RAM by default.
# cpuset test requires >= 8 CPUs
_rt_cpu_resources_set 8

# --install provides a list of binaries that should be included in the VM image.
# Dracut will resolve shared object dependencies and add them automatically.
_rt_require_conf_dir KSELFTEST_DIR
# convert kselftest suite:name format to file paths for install
req_inst=($(awk -F ":" -v d="$KSELFTEST_DIR" '{printf "%s/%s/%s ",d,$1,$2}' \
	"${KSELFTEST_DIR}/kselftest-list.txt"))

# --add-drivers provides a list of kernel modules, which will be obtained from
# the rapido.conf KERNEL_INSTALL_MOD_PATH

# --modules provides a list of *Dracut* modules. See Dracut documentation for
# details
"$DRACUT" \
	--install "awk basename cut date dirname echo expr fmt grep head id
	           lscpu ps realpath rmdir sort uniq wc resize seq dd bc
	           mkswap swapon swapoff mkfs.ext4 which ${req_inst[*]}" \
	--include "$KSELFTEST_DIR" "$KSELFTEST_DIR" \
	--modules "base dracut-systemd" \
	--add-drivers "zram lzo lzo-rle ext4" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"
