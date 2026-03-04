#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE S.A. 2018-2025, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_fstests
req_inst=()
_rt_require_btrfs_progs req_inst
_rt_require_pam_mods req_inst "pam_rootok.so" "pam_limits.so"
_rt_human_size_in_b "${FSTESTS_ZRAM_SIZE:-1G}" zram_bytes \
	|| _fail "failed to calculate memory resources"
# need enough memory for five zram devices
mem_rsc="$((3072 + (zram_bytes * 5 / 1048576)))M"

printf -v req_inst_bins 'bin %s\n' "${req_inst[@]}"

PATH="target/release:${PATH}"
rapido-cut --manifest /dev/stdin <<EOF
file /rapido-rsc/mem/${mem_rsc}

autorun autorun/lib/fstests.sh autorun/fstests_btrfs.sh $*

$req_inst_bins
bin ls
bin cat
bin mkdir
bin cp
bin mv
bin rm
bin ln
bin sed
bin readlink
bin sleep
bin umount
bin findmnt
bin dmesg
bin uname
bin tail
bin blockdev
bin ps
bin rmdir
bin dd
bin grep
bin find
bin df
bin sha256sum
bin strace
bin mkfs
bin mkfs.ext4
bin e2fsck
bin tune2fs
bin shuf
bin free
bin ip
bin su
bin which
bin perl
bin awk
bin bc
bin touch
bin cut
bin chown
bin chmod
# xfstests hardcoded
bin /bin/true
bin false
bin unlink
bin mktemp
bin getfattr
bin setfattr
bin chacl
bin attr
bin killall
bin hexdump
bin sync
bin id
bin sort
bin uniq
bin date
bin expr
bin tac
bin diff
bin head
bin dirname
bin seq
bin basename
bin tee
bin egrep
bin yes
bin mkswap
bin timeout
bin realpath
bin blkdiscard
bin fstrim
bin logger
bin chattr
bin lsattr
bin cmp
bin stat
bin hostname
bin getconf
bin md5sum
bin od
bin wc
bin getfacl
bin setfacl
bin tr
bin xargs
bin sysctl
bin link
bin truncate
bin quota
bin repquota
bin setquota
bin quotacheck
bin quotaon
bin pvremove
bin vgremove
bin xfs_mkfile
bin xfs_db
bin xfs_io
bin wipefs
bin filefrag
bin losetup
bin chgrp
bin du
bin fgrep
bin pgrep
bin tar
bin rev
bin kill
bin swapon
bin swapoff
bin xfs_freeze
bin fsck
bin ipcmk
bin ipcs
bin ipcrm
bin blkid
bin mkfifo
bin mknod
bin flock

# udev needed for dm devices
bin dmsetup
bin udevadm
bin systemd-udevd
# TODO: we should only need dm rules - generate on boot?
tree /usr/lib/udev/rules.d /usr/lib/udev/rules.d

# rapido-cut adds bash by default, but xfstests hardcodes /bin/bash so make
# sure we have it there (as a symlink)
bin /bin/bash
# /bin/sh is also used
slink /bin/sh /bin/bash
# btrfs/058 calls xfs_io interactively; silence "Cannot read termcap database"
try-bin /usr/share/terminfo/l/linux

try-bin dbench
try-bin /usr/share/dbench/client.txt
try-bin duperemove
try-bin fsverity
try-bin keyctl
try-bin openssl
try-bin /etc/ssl/openssl.cnf
try-bin nano
try-bin fio
try-bin setcap
try-bin getcap
try-bin capsh

filter ${FSTESTS_SRC}/.git
bin $FSTESTS_SRC

kmod btrfs
kmod zram
kmod lzo
kmod lzo_rle
kmod raid6_pq
kmod xxhash_generic

try-kmod loop
try-kmod dm_snapshot
try-kmod dm_flakey
try-kmod scsi_debug
try-kmod dm_log_writes
try-kmod ext4
# only needed if passing through devs instead of zram...
try-kmod virtio_blk
EOF
