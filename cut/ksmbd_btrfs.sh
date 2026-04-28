#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE S.A. 2023-2026, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

req_inst=()
_rt_require_ksmbd_tools req_inst
_rt_human_size_in_b "${FSTESTS_ZRAM_SIZE:-1G}" zram_bytes \
	|| _fail "failed to calculate memory resources"
_rt_require_conf_setting CIFS_USER CIFS_PW CIFS_SHARE
printf -v req_inst_bins 'bin %s\n' "${req_inst[@]}"

PATH="target/release:${PATH}"
rapido-cut --manifest /dev/stdin <<EOF
file /rapido-rsc/mem/$((1024 + (zram_bytes / 1048576)))M
include net.fest

autorun autorun/ksmbd_btrfs.sh $*

$req_inst_bins
bin awk
bin cat
bin chmod
bin cut
bin date
bin dd
bin df
bin diff
bin dirname
bin dirname
bin expr
bin false
bin find
bin getfacl
bin getfattr
bin grep
bin head
bin id
bin killall
bin ln
bin ls
bin mkdir
bin mkfs
bin mkfs.btrfs
bin ps
bin resize
bin rmdir
bin seq
bin setfacl
bin setfattr
bin sha256sum
bin sleep
bin sort
bin stat
bin strace
bin sync
bin tac
bin tail
bin touch
bin true
bin uniq
bin which

kmod aes
kmod btrfs
kmod ccm
kmod cmac
kmod crc32
kmod ecb
kmod gcm
kmod hmac
kmod ksmbd
kmod lzo
kmod lzo-rle
kmod md5
kmod sha256
kmod sha512
kmod zram
EOF
