#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

[[ -d "${KERNEL_SRC}" ]] || \
  _fail "specify a valid KERNEL_SRC in rapido.conf"

[[ -d "$KERNEL_INSTALL_MOD_PATH" ]] || \
  _fail "specify a valid KERNEL_INSTALL_MOD_PATH in rapido.conf"

[[ -n ${NET_TEST_KMOD} ]] || \
  _fail "specify a kernel module to test in rapido.conf"

[[ -d "$NET_TEST_SUITE" && -x "$NET_TEST_SUITE/start.sh" ]] || \
  _fail "specify the test suite directory containing start.sh"

_rt_require_dracut_args "$RAPIDO_DIR/autorun/net_test.sh" "$@"
_rt_cpu_resources_set "2"
_rt_mem_resources_set "256M"

NET_TEST_TOOLS="\
	bridge \
	dhclient \
	dirname basename realpath \
	dmesg \
	ethtool \
	grep \
	hostname \
	ip \
	iperf3 \
	lspci \
	nc \
	ping \
"

# ideally dracut would fail if the specified module cannot be found,
# but it exits with 0 (tested version 059-15.fc39)
"$DRACUT" \
	--install "${NET_TEST_TOOLS}" \
	--add-drivers "af_packet ${NET_TEST_KMOD}.ko" \
	--modules "base" \
	--include "${KERNEL_SRC}/samples/pktgen" "pktgen" \
	--include "${NET_TEST_SUITE}" "driver-tests" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"
