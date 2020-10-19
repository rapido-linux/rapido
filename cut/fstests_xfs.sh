#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2016, all rights reserved.
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

_rt_require_dracut_args "$RAPIDO_DIR/autorun/fstests_xfs.sh"
_rt_require_fstests

"$DRACUT" --install "$DRACUT_RAPIDO_INSTALL \
		tail blockdev ps rmdir resize dd vim grep find df sha256sum \
		strace mkfs mkfs.xfs free \
		which perl awk bc touch cut chmod true false unlink \
		mktemp getfattr setfattr chacl attr killall hexdump sync \
		id sort uniq date expr tac diff head dirname seq \
		basename tee egrep yes \
		fstrim fio logger dmsetup chattr lsattr cmp stat \
		dbench /usr/share/dbench/client.txt hostname getconf md5sum \
		od wc getfacl setfacl tr xargs sysctl link truncate quota \
		repquota setquota quotacheck quotaon pvremove vgremove \
		xfs_mkfile xfs_db xfs_io fsck \
		xfs_mdrestore xfs_bmap xfs_fsr xfsdump xfs_freeze xfs_info \
		xfs_logprint xfs_repair xfs_growfs xfs_quota xfs_metadump \
		chgrp du fgrep pgrep tar rev kill duperemove \
		${FSTESTS_SRC}/ltp/* ${FSTESTS_SRC}/src/* \
		${FSTESTS_SRC}/src/log-writes/* \
		${FSTESTS_SRC}/src/aio-dio-regress/*" \
	--include "$FSTESTS_SRC" "$FSTESTS_SRC" \
	$DRACUT_RAPIDO_INCLUDES \
	--add-drivers "zram lzo lzo-rle dm-snapshot dm-flakey xfs" \
	--modules "bash base" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT || _fail "dracut failed"

_rt_xattr_vm_networkless_set "$DRACUT_OUT"
_rt_xattr_vm_resources_set "$DRACUT_OUT" "2" "2048M"
