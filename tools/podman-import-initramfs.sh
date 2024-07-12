#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2022, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

# Import an existing rapido initramfs image into podman so that it can be
# explored via e.g. "podman run -it sha256:... /bin/bash". The regular rapido
# autorun boot path can triggered via "bash --login", but will fail for now
# without further tweaks.

unwind=""
trap "eval \$unwind" 0

t=$(mktemp --directory "rapido-cpio-to-tar.XXXXXXXXXX")
[[ -d $t ]] || _fail "mktemp failed"
unwind="rm -rf \"${t}\"; $unwind"

# "podman import" doesn't natively support cpio so we need to transcode to tar
cpio -D "$t" -idm < "$DRACUT_OUT" \
	|| _fail "failed to extract image at ${RAPIDO_DIR}/initrds/myinitrd"

tar -C "$t" --to-stdout -c . | podman import -m="Imported from rapido" "$@" - \
	|| _fail "podman import failed"
