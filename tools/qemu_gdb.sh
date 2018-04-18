#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2018, all rights reserved.
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

# Connect to a running QEMU gdb server

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

# sanity check rapido.conf
[ -z "$KERNEL_SRC" ] && _fail "KERNEL_SRC not set"
[ -f "${KERNEL_SRC}/vmlinux" ] || _fail "vmlinux not found. Build needed?"
[ -z "$QEMU_EXTRA_ARGS" ] \
       	&& _fail "QEMU_EXTRA_ARGS not set - should contain -s or -gdb"

opts=$(getopt -q -o "s" -a --long "gdb:" -- $QEMU_EXTRA_ARGS)
[ -z "$opts" ] && _fail "failed to parse -s or -gdb in QEMU_EXTRA_ARGS"
eval set -- "$opts"

gdb_dev=""
while [ -n "$1" ]; do
	case "$1" in
		-s)
			gdb_dev="tcp::1234"
			shift
			;;
		--gdb)
			gdb_dev=$2
			shift 2
			;;
		*)
			break
			;;
	esac
done
[ -z "$gdb_dev" ] \
	&& _fail "no gdbserver device found in QEMU_EXTRA_ARGS"

echo "connecting to gdbserver at ${gdb_dev}..."
cd ${KERNEL_SRC}
gdb ${KERNEL_SRC}/vmlinux \
	-ex "add-auto-load-safe-path $KERNEL_SRC" \
	-ex "add-auto-load-scripts-directory ${KERNEL_SRC}/scripts/gdb/" \
	-ex "target remote ${gdb_dev}"
