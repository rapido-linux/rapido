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
_rt_cpu_resources_set "2"
_rt_mem_resources_set "2048M"	# 2 vCPUs, 2G RAM

"$DRACUT" \
	--install "tail blockdev ps rmdir resize dd grep find df mkfs which \
		perl awk bc touch cut chmod true false unlink mktemp getfattr \
		setfattr attr killall hexdump sync id sort uniq date expr tac \
		diff head dirname seq basename tee egrep yes dmsetup chattr \
		lsattr cmp stat hostname getconf md5sum od wc tr xargs sysctl \
		link truncate quota quotacheck quotaon vgremove chgrp du fgrep \
		pgrep pkill tar rev kill fdformat ldd free losetup chown sed \
		cat lsmod ip ping tc \
		${LTP_DIR}/bin/* ${LTP_DIR}/testcases/bin/*" \
	--include "$LTP_DIR" "$LTP_DIR"  \
	--include "${KERNEL_SRC}/.config" /.config \
	--add-drivers "loop" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"
