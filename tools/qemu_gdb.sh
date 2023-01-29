#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2018-2023, all rights reserved.

# Connect to a running QEMU gdb server

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

# sanity check rapido.conf
[ -z "$KERNEL_SRC" ] && _fail "KERNEL_SRC not set"
[ -f "${KERNEL_SRC}/vmlinux" ] || _fail "vmlinux not found. Build needed?"
[ -z "$QEMU_EXTRA_ARGS" ] \
       	&& _fail "QEMU_EXTRA_ARGS not set - should contain -s or -gdb"
[[ $QEMU_EXTRA_KERNEL_PARAMS == "${QEMU_EXTRA_KERNEL_PARAMS/nokaslr/}" ]] \
   && grep "CONFIG_RANDOMIZE_BASE=y" "${KERNEL_SRC}/.config" \
   && echo "WARNING: KASLR enabled: consider booting with nokaslr"

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
cd "$KERNEL_SRC"
gdb -q "${KERNEL_SRC}/vmlinux" \
	-iex "set auto-load safe-path $KERNEL_SRC" \
	-ex "add-auto-load-safe-path $KERNEL_SRC" \
	-ex "add-auto-load-scripts-directory ${KERNEL_SRC}/scripts/gdb/" \
	-ex "target remote ${gdb_dev}" \
	-ex "lx-symbols"
