#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2021-2022, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args "$RAPIDO_DIR/autorun/uring_xfs.sh" "$@"
_rt_require_conf_dir LIBURING_SRC
_rt_mem_resources_set "2G"

test_manifest="$(mktemp --tmpdir iouring_tests.XXXXX)"
trap "rm $test_manifest" 0 1 2 3 15

test_files=( $(find "${LIBURING_SRC}/test" -type f -executable ! -name '*.sh' \
		-fprintf "$test_manifest" '%f\n' -printf '%p ') )
test_files+=("${LIBURING_SRC}/test/runtests.sh")
[[ -f "${LIBURING_SRC}/test/config.local" ]] \
	&& test_files+=("${LIBURING_SRC}/test/config.local")	# optional conf

if [[ -d $KERNEL_SRC ]]; then
	# add kernel iouring test tools if built via "make -C tools/io_uring"
	for i in tools/io_uring/io_uring-bench tools/io_uring/io_uring-cp; do
		[[ -x ${KERNEL_SRC}/${i} ]] && test_files+=("${KERNEL_SRC}/${i}")
	done
fi

"$DRACUT" --install "tail ps rmdir resize dd vim grep find df sha256sum \
		   strace mkfs mkfs.xfs tee timeout ip \
		   stat which touch cut chmod true false \
		   id sort uniq date expr tac diff head dirname seq \
		   ${test_files[*]}" \
	--include "$test_manifest" "/uring_tests.manifest" \
	--add-drivers "xfs zram lzo lzo-rle" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"
