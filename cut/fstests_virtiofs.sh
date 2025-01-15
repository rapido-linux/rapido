#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2025, all rights reserved
#
# Server can be started via e.g.
# virtiofsd \
#	--socket-path="${RAPIDO_DIR}/vfsd.sock" \
#	--shared-dir "$share_dir" \
#	--announce-submounts --inode-file-handles=mandatory

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args "$RAPIDO_DIR/autorun/lib/fstests.sh" \
			"$RAPIDO_DIR/autorun/fstests_virtiofs.sh" "$@"
_rt_require_networking
_rt_require_fstests
pam_paths=()
_rt_require_pam_mods pam_paths "pam_rootok.so" "pam_limits.so"
_rt_mem_resources_set "2048M"

[[ $QEMU_EXTRA_ARGS =~ vhost-user-fs-pci,[^[:space:]]*,tag=TEST_DEV([, ]|$) ]] \
	|| _fail "$(cat <<EOF
This runner requires one vhost-user-fs-pci device with "TEST_DEV" as device tag
identifier, e.g.
QEMU_EXTRA_ARGS="... -chardev socket,id=c0,path=\${RAPIDO_DIR}/vfsd.sock \\
		-device vhost-user-fs-pci,chardev=c0,tag=TEST_DEV \\
		-object memory-backend-memfd,id=mem,size=2G,share=on -numa node,memdev=mem"
EOF
)"

"$DRACUT" --install "tail blockdev ps rmdir resize dd vim grep find df sha256sum \
		   strace mkfs free su \
		   which perl awk bc touch cut chmod true false unlink \
		   mktemp getfattr setfattr chacl attr killall hexdump sync \
		   id sort uniq date expr tac diff head dirname seq \
		   basename tee egrep yes \
		   fstrim fio logger dmsetup chattr lsattr cmp stat \
		   dbench /usr/share/dbench/client.txt hostname getconf md5sum \
		   od wc getfacl setfacl tr xargs sysctl link truncate quota \
		   repquota setquota quotacheck quotaon pvremove vgremove \
		   xfs_mkfile xfs_db xfs_io \
		   chgrp du fgrep pgrep tar rev kill ${pam_paths[*]} \
		   ${FSTESTS_SRC}/ltp/* ${FSTESTS_SRC}/src/* \
		   ${FSTESTS_SRC}/src/log-writes/* \
		   ${FSTESTS_SRC}/src/aio-dio-regress/*" \
	--include "$FSTESTS_SRC" "$FSTESTS_SRC" \
	--add-drivers "virtiofs" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"
