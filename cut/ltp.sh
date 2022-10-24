#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2019, all rights reserved.
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

_rt_require_dracut_args "$RAPIDO_DIR/autorun/ltp.sh" "$@"
_rt_require_conf_dir LTP_DIR
_rt_mem_resources_set "2048M"	# 2 vCPUs, 2G RAM

if [[ -n $KERNEL_SRC ]]; then
	config="${KERNEL_SRC}/.config"
else
	config="/boot/config-$(uname -r)"
fi

fses=(btrfs exfat ext2 ext3 ext4 fuse ntfs vfat xfs)

"$DRACUT" \
	--install " \
		attr awk basename bc blockdev cat chattr chgrp chmod chown cmp cut date
		dd df diff dirname dmsetup du egrep exportfs expr false fdformat fdisk
		fgrep find free gdb getconf getfacl getfattr grep head hexdump hostname
		id ip kill killall ldd link losetup lsattr lsmod ltrace md5sum
		${fses[*]/#/mkfs.} mktemp ${fses[*]/#/mount.} od parted perl pgrep ping
		ping6 pkill ps quota quotacheck quotaon resize rev rmdir sed seq
		setfacl setfattr sort stat strace sync sysctl tac tail tar tc tee touch
		tr true truncate uniq unlink vgremove wc which xargs xxd yes
		${LTP_DIR}/bin/* ${LTP_DIR}/testcases/bin/*" \
	--include "$LTP_DIR" "$LTP_DIR"  \
	--include "$config" /.config \
	--add-drivers "loop" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"
