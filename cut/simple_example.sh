#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE S.A. 2018-2025, all rights reserved.

# Rapido cut scripts generate VM root (initramfs) images. The image is described
# to rapido-cut.rs via a manifest file, which is processed in top-to-bottom
# order with following format:

# "autorun LOCATION [LOCATION ...]" specifies script paths that will be
# installed and run (in order) on VM boot.

# "bin ELF" specifies a single ELF binary which is searched for under BIN_PATHS.
# ELF metadata is parsed to determine and archive shared-object dependencies.
# "try-bin ELF" is the same as "bin", but won't abort if the file is not found.

# "tree NAME LOCATION" copies a specific file or directory-tree from LOCATION to
# the given archive destination NAME.

# "kmod MODULE" specifies a kernel module to be obtained from the rapido.conf
# KERNEL_INSTALL_MOD_PATH directory, or host kernel modules directory if unset.
# The kernel's modules.dep file is parsed to determine and archive dependency
# modules.

# "file NAME LOCATION" specifies a file to be archived at path NAME, with data
# and metadata obtained from the local file at LOCATION.

# "dir NAME" adds a directory with path NAME to the archive.

# "slink NAME TARGET" adds a symbolic link to the archive.

# "include MANIFEST" can be used to process an external manifest file. External
# manifests are processed in-place with regard to ordering.

PATH="target/release:${PATH}"
rapido-cut --manifest /dev/stdin <<EOF
autorun autorun/simple_example.sh $*

bin ls
bin cat
bin sleep
bin ps
bin mkdir
bin rmdir
bin dd
try-bin nano
EOF

# rapido-cut writes the initramfs image to the rapido.conf DRACUT_OUT specified
# path, or an explicit path provided via --output parameter.

# rapido-vm boots images with 2 vCPUs and 512M RAM by default. These
# defaults can be changed, e.g. 1 vCPU + 1G RAM could be specified via:
#file /rapido-rsc/cpu/1
#file /rapido-rsc/mem/1G

# rapido VMs are not networked by default. To add networking configuration
# (see rapido.conf NET_CONF) and systemd-network dependencies to the image,
# a manifest/net.fest file is provided as a convenience. It can be used via:
#include net.fest
