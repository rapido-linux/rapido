#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2021, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args "$RAPIDO_DIR/autorun/initramfs_gen_init_cpio.sh" "$@"

tmp_vdata="$(mktemp --tmpdir -d vdata.XXXXXXXX)"
# remove tmp once we're done
trap "rm -f \"${tmp_vdata}\"/{fiod*,*.state}; rmdir \"$tmp_vdata\"" 0 1 2 3 15

fio --directory="${tmp_vdata}" --aux-path="${tmp_vdata}" \
	--name=verify-wr --rw=write --size=1M --verify=crc32c \
	--filename=fiod || _fail "fio failed to write verification data"

fio --directory="${tmp_vdata}" --aux-path="${tmp_vdata}" \
	--name=verify-wr-small --rw=write --size=4099 --verify=crc32c \
	--filename=fiod-small || _fail "fio failed to write verification data"

"$DRACUT" \
	--install "resize fio strace" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"

# verification data is appended as a separate cpio archive using gen_init_cpio
cat >"${tmp_vdata}/fiod.gen_init_cpio.manifest" <<EOF
# gen_init_cpio manifest expands \${envvar} locations
dir /vdata 0700 0 0
file /vdata/fiod \${tmp_vdata}/fiod 0600 0 0 /vdata/fiod-hlink
file /vdata/fiod-small \${tmp_vdata}/fiod-small 0600 0 0
slink vdata-slink /vdata 0700 0 0
EOF

export tmp_vdata
# TODO: gen_init_cpio -c option requires the kernel patchset
# initramfs: "crc" cpio format and INITRAMFS_PRESERVE_MTIME
"${KERNEL_SRC}/usr/gen_init_cpio" "${tmp_vdata}/fiod.gen_init_cpio.manifest" \
	>> "$DRACUT_OUT" \
	|| _fail "gen_init_cpio failed"

_rt_xattr_vm_networkless_set "$DRACUT_OUT"
_rt_xattr_vm_resources_set "$DRACUT_OUT" "2" "1024M"
