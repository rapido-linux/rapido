#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE S.A. 2018-2025, all rights reserved.

# The job of Rapido cut scripts is to generate a VM image. This is done using
# rapido-cut with a number of parameters...

# --autorun specifies script paths that will be installed and run (in order) on
# VM boot.

# --install provides a list of binaries that should be included in the VM image.
# Dracut will resolve shared object dependencies and add them automatically.

# --include copies a specific file or directory-tree to the given image
# destination. --try-install is similar but won't abort if missing.

# --kmods provides a list of kernel modules, which will be obtained from
# the rapido.conf KERNEL_INSTALL_MOD_PATH directory, or host kernel modules
# directory if unset.
PATH="target/release:${PATH}"
rapido-cut \
	--autorun "autorun/simple_example.sh $*" \
	--install "ls cat sleep ps rmdir dd mkfs.xfs" \
	--try-install "resize" \
	--kmods "zram lzo lzo_rle"

# rapido-cut writes the initramfs image to the rapido.conf DRACUT_OUT specified
# path, or an explicit path provided via --output parameter.

# rapido-vm boots images with 2 vCPUs and 512M RAM by default. These
# defaults can be changed, e.g. 1 vCPU + 1G RAM could be specified via:
#--include "dracut.conf.d/.empty /rapido-rsc/cpu/1"
#--include "dracut.conf.d/.empty /rapido-rsc/mem/1G"

# rapido VMs are not networked by default. To add networking configuration
# (see rapido.conf NET_CONF) and systemd-network dependencies to the image,
# append the parameter: --net
