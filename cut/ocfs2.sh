#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2023, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args "$RAPIDO_DIR/autorun/ocfs2.sh" "$@"
_rt_require_networking
_rt_mem_resources_set "1024M"

[[ $QEMU_EXTRA_ARGS =~ serial=OCFS2([, ]|$) ]] || _fail "$(cat <<EOF
This runner requires one shared block device between all VMs, with "OCFS2"
as device serial identifier, e.g.
QEMU_EXTRA_ARGS="... -drive if=none,id=o2,file=/tmp/o2dev,cache=none,format=raw,file.locking=off -device virtio-blk-pci,drive=o2,serial=OCFS2"
EOF
)"

"$DRACUT" --install "tail blockdev ps rmdir resize dd vim grep find df \
		   strace xargs timeout \
		   which awk touch cut chmod true false \
		   getfattr setfattr chacl attr killall sync \
		   id sort uniq date expr tac diff head dirname seq \
		   o2cb mkfs.ocfs2 mount.ocfs2 fsck.ocfs2" \
	--modules "base" \
	--drivers "virtio_blk ocfs2 ocfs2_stack_o2cb ocfs2_dlm dlm" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"
