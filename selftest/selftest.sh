#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2019, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."

export RAPIDO_SELFTEST_TMPDIR="$(mktemp -d rapido-selftest.XXXXXXX)"
[ -d "$RAPIDO_SELFTEST_TMPDIR" ] || exit 1
CLEANUP="rm -f ${RAPIDO_SELFTEST_TMPDIR}/*; rmdir $RAPIDO_SELFTEST_TMPDIR"
# cleanup tmp dir when done
trap "$CLEANUP" 0 1 2 3 15

_usage() {
	echo -e "usage:\n"
		"\tKERNEL_SRC=/path/to/kernel/ " \
		"KERNEL_INSTALL_MOD_PATH=/path/to/kernel/mods selftest.sh [test_filter]"
	exit 1
}

_fail() {
	echo "error: $*"
	exit 1
}

_generate_conf() {
	local conf="$1"
	local example_conf="${RAPIDO_DIR}/rapido.conf.example"
	local i val

	[ -f "$conf" ] && _fail "$conf already exists, aborting"

	cp "$example_conf" "$conf" || _fail "cp failed"
	echo "# Rapido selftest changes..." >> "$conf"

	for i in KERNEL_SRC KERNEL_INSTALL_MOD_PATH; do
		eval "val=\${$i}"
		if [ -n "$val" ]; then
			[ -d "$val" ] || _fail "$i is not a directory"
		else
			echo "$i not set, using locally installed kernel"
		fi

		echo "${i}=\"${val}\"" >> "$conf" || _fail "write failed"
	done

	# set QEMU_EXTRA_KERNEL_PARAMS= so that printk doesn't go to console
	echo "QEMU_EXTRA_KERNEL_PARAMS=\"loglevel=0\"" >> "$conf" \
		|| _fail "write failed"
	echo "QEMU_EXTRA_ARGS=\"-monitor none -serial stdio -nographic -device virtio-rng-pci\"" \
		>> "$conf" || _fail "write failed"
}

_run_tests() {
	local filter="$1"
	local tnum=0
	local t

	for t in $(ls "selftest/test/"${filter}); do
		if ! [ -x "${t}" ]; then
			echo "$t skipped"
			continue
		fi
		echo "$t running"
		${t} || _fail "test $t failed with $?"
		(( tnum++ ))
	done

	echo "All $tnum tests passed"
}

FILTER="$1"
if [ -n "$FILTER" ]; then
	[ "$FILTER" == "${FILTER#*/}" ] || _fail "filter can't include /"
	[ "$FILTER" == "${FILTER#*.}" ] || _fail "filter can't include ."
else
	FILTER="???"	# match all three digit tests by default
fi

# QEMU_EXTRA_X are explicitly set during selftest
[ -z "$QEMU_EXTRA_ARGS" ] || _fail "QEMU_EXTRA_ARGS is set"
[ -z "$QEMU_EXTRA_KERNEL_PARAMS" ] || _fail "QEMU_EXTRA_KERNEL_PARAMS is set"

_generate_conf "${RAPIDO_SELFTEST_TMPDIR}/rapido.conf"
export RAPIDO_CONF="${RAPIDO_SELFTEST_TMPDIR}/rapido.conf"
export RAPIDO_SELFTEST_TMPDIR="$RAPIDO_SELFTEST_TMPDIR"

pushd "${RAPIDO_DIR}"

_run_tests "$FILTER"

popd
