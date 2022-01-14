#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2018-2021, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

# Call _rt_require_dracut_args() providing script paths that will be included
# and run on VM boot. It exports variables used in the dracut invocation below.
_rt_require_dracut_args "$RAPIDO_DIR/autorun/simple_example.sh" "$@"

# The job of Rapido cut scripts is to generate a VM image. This is done using
# Dracut with the following parameters...

# --install provides a list of binaries that should be included in the VM image.
# Dracut will resolve shared object dependencies and add them automatically.

# --include copies a specific file or directory to the given image destination.

# --add-drivers provides a list of kernel modules, which will be obtained from
# the rapido.conf KERNEL_INSTALL_MOD_PATH

# --modules provides a list of *Dracut* modules. See Dracut documentation for
# details
"$DRACUT" \
	--install "resize ps rmdir dd mkfs.xfs" \
	--add-drivers "zram lzo lzo-rle" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"

# VMs can be deployed with or without a virtual network adapter. The default is
# to deploy *with* network, in which case the ip and ping binaries should be
# added to the Dracut --install parameter above.
_rt_xattr_vm_networkless_set "$DRACUT_OUT"		# *disable* network

# VMs are booted with 2 vCPUs and 512M RAM by default. These defaults can be
# changed using _rt_xattr_vm_resources_set.
#_rt_xattr_vm_resources_set "$DRACUT_OUT" "2" "2048M"	# 2 vCPUs, 2G RAM
