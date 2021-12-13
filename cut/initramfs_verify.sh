#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2021, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args "$RAPIDO_DIR/autorun/initramfs_verify.sh" "$@"

tmp_vdata="$(mktemp --tmpdir -d vdata.XXXXXXXX)"
# remove tmp once we're done
trap "rm -f ${tmp_vdata}/{fiod*,*verify.state}; rmdir $tmp_vdata" 0 1 2 3 15

fio --directory="${tmp_vdata}" --aux-path="${tmp_vdata}" \
	--name=verify-wr --rw=write --size=1M --verify=crc32c \
	--filename=fiod || _fail "fio failed to write verification data"

"$DRACUT" \
	--install "resize fio" \
	--include "${tmp_vdata}/fiod" "/fiod" \
	$DRACUT_RAPIDO_INCLUDES \
	--modules "base" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT || _fail "dracut failed"

_rt_xattr_vm_networkless_set "$DRACUT_OUT"
_rt_xattr_vm_resources_set "$DRACUT_OUT" "2" "1024M"
