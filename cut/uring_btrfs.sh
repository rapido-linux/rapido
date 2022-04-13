#!/bin/bash
#
# Copyright (C) SUSE LLC 2021, all rights reserved.
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

_rt_require_dracut_args "$RAPIDO_DIR/autorun/uring_btrfs.sh" "$@"
_rt_require_conf_dir LIBURING_SRC

test_manifest="$(mktemp --tmpdir iouring_tests.XXXXX)"
# remove tmp file once we're done
trap "rm $test_manifest" 0 1 2 3 15

pushd ${LIBURING_SRC}/test || _fail
find . -type f -executable ! -name '*.sh' -fprintf "$test_manifest" '%P\n'
popd
test_bins=$(sed "s#^#${LIBURING_SRC}/test/#" "$test_manifest")

"$DRACUT" --install "tail ps rmdir resize dd vim grep find df sha256sum \
		   strace mkfs mkfs.btrfs tee timeout \
		   stat which touch cut chmod true false \
		   id sort uniq date expr tac diff head dirname seq \
		   ${LIBURING_SRC}/test/runtests.sh \
		   $test_bins" \
	--include "$test_manifest" "/uring_tests.manifest" \
	--add-drivers "zram lzo lzo-rle btrfs" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"
