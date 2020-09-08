#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2018, all rights reserved.
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

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args

# The job of Rapido cut scripts is to generate a VM image. This is done using
# Dracut with the following parameters...

# --install provides a list of binaries that should be included in the VM image.
# Dracut will resolve shared object dependencies and add them automatically.

# --include copies a specific file or directory to the given image destination.
# The .profile image path is special, in that it is executed on boot.

# --add-drivers provides a list of kernel modules, which will be obtained from
# the rapido.conf KERNEL_INSTALL_MOD_PATH

# --modules provides a list of *Dracut* modules. See Dracut documentation for
# details

# DRACUT_EXTRA_ARGS in rapido.conf allows for extra custom Dracut parameters for
# debugging, etc.
"$DRACUT" \
	--install "ps rmdir dd mkfs.xfs" \
	--include "$RAPIDO_DIR/autorun/simple_example.sh" "/.profile" \
	$DRACUT_RAPIDO_INCLUDES \
	--add-drivers "zram lzo lzo-rle" \
	--modules "bash base" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT || _fail "dracut failed"

# VMs can be deployed with or without a virtual network adapter. The default is
# to deploy *with* network, in which case the ip and ping binaries should be
# added to the Dracut --install parameter above.
_rt_xattr_vm_networkless_set "$DRACUT_OUT"		# *disable* network

# VMs are booted with 2 vCPUs and 512M RAM by default. These defaults can be
# changed using _rt_xattr_vm_resources_set.
#_rt_xattr_vm_resources_set "$DRACUT_OUT" "2" "2048M"	# 2 vCPUs, 2G RAM
