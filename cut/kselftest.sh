#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2018-2026, all rights reserved.

PATH="target/release:${PATH}"
rapido-cut --manifest /dev/stdin <<EOF
# cpuset test requires >= 8 CPUs
file /rapido-rsc/cpu/8

include systemd.fest
autorun autorun/kselftest.sh $*

# variable substitution fails if KSELFTEST_DIR is unset in rapido.conf. "bin"
# recursively pulls in all children along with ELF shared-object dependencies.
bin \${KSELFTEST_DIR}

bin awk
bin basename
bin bc
bin cat
bin chmod
bin cut
bin date
bin dd
bin dirname
bin echo
bin expr
bin fmt
bin grep
bin head
bin id
bin ls
bin lscpu
bin mkdir
bin mkfs.ext4
bin mkswap
bin ps
bin realpath
bin rm
bin rmdir
bin sed
bin seq
bin sleep
bin sort
bin swapoff
bin swapon
bin touch
bin uniq
bin wc
bin which
# scripts hardcode a few paths which need to exist
bin /bin/sh
bin /bin/bash
bin /usr/bin/timeout
bin /usr/bin/env

kmod ext4
kmod lzo
kmod lzo_rle
kmod zram
EOF
