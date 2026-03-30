#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE S.A. 2019-2026, all rights reserved.
PATH="target/release:${PATH}"
rapido-cut --manifest /dev/stdin <<EOF
include net.fest

autorun autorun/cifs.sh $*

bin mount.cifs
bin cifs.upcall
bin attr
bin basename
bin cat
bin chacl
bin chattr
bin chmod
bin cut
bin dd
bin df
bin dirname
bin dmesg
bin du
bin false
bin find
bin fstrim
bin getfacl
bin getfattr
bin grep
bin killall
bin ls
bin lsattr
bin mkdir
bin ps
bin rm
bin rmdir
bin seq
bin setfacl
bin setfattr
bin sleep
bin stat
bin sync
bin tail
bin touch
bin true
bin truncate
bin umount
bin unlink
bin which
try-bin nano

kmod ccm
kmod cifs
kmod cmac
kmod ctr
kmod gcm
EOF
