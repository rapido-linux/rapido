#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2021, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args "$RAPIDO_DIR/autorun/initramfs_verify.sh" "$@"

tmp_vdata="$(mktemp --tmpdir -d vdata.XXXXXXXX)"
# remove tmp once we're done
trap "rm -rf ${tmp_vdata}/{fiod*,*verify.state}; rmdir $tmp_vdata" 0 1 2 3 15

fio --directory="${tmp_vdata}" --aux-path="${tmp_vdata}" \
	--name=verify-wr --rw=write --size=1M --verify=crc32c \
	--filename=fiod || _fail "fio failed to write verification data"
touch --date=@1641548270 "${tmp_vdata}/fiod"

"$DRACUT" \
	--install "resize fio stat" \
	--include "${tmp_vdata}/fiod" "/fiod" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"

# As of 889d51a10712 (v2.6.28) kernel initramfs extraction preserves archived
# mtimes by default.
# Dracut doesn't always preserve directory mtimes through the staging area, so
# append as a separate cpio archive.
if ! grep -q "^# CONFIG_INITRAMFS_PRESERVE_MTIME" "$KCONFIG"; then
	mkdir -p "${tmp_vdata}/fiod.mtime_chk/2"
	touch --date=@1641548271 "${tmp_vdata}/fiod.mtime_chk"
	touch --date=@1641548272 "${tmp_vdata}/fiod.mtime_chk/2"
	echo -e "fiod.mtime_chk\nfiod.mtime_chk/2" \
	  | cpio -o -H newc -D "$tmp_vdata"  >> "$DRACUT_OUT" \
		|| _fail "failed to append mtime_chk archive"
fi
