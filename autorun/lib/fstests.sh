#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2022, all rights reserved.

_fstests_devs_zram_setup() {
	local cfg_var="$1"
	local zram_num

	zram_num="$(cat /sys/class/zram-control/hot_add)" \
		|| _fatal "zram hot add failed"
	echo "${FSTESTS_ZRAM_SIZE:-1G}" > \
		/sys/devices/virtual/block/zram${zram_num}/disksize \
		|| _fatal "failed to set size for $zram_num"
	_CFG[$cfg_var]="/dev/zram${zram_num}"
}

# any dev with a serial number matching an fstests param will be used
_fstests_devs_provision() {
	local cfg_path="$1"
	local i ser
	declare -A _CFG=(["SCRATCH_DEV"]="" ["SCRATCH_LOGDEV"]="" \
			 ["SCRATCH_RTDEV"]="" ["TEST_DEV"]="")

	for i in $(ls /sys/block); do
		ser="$(cat /sys/block/${i}/serial 2>/dev/null)" || continue
		[[ -v "_CFG[$ser]" ]] && _CFG[$ser]="/dev/${i}"
	done

	[ -b "${_CFG[TEST_DEV]}" ] || _fstests_devs_zram_setup TEST_DEV
	[ -b "${_CFG[SCRATCH_DEV]}" ] || _fstests_devs_zram_setup SCRATCH_DEV
	[ -b "${_CFG[SCRATCH_LOGDEV]}" ] || unset _CFG[SCRATCH_LOGDEV]
	[ -b "${_CFG[SCRATCH_RTDEV]}" ] || unset _CFG[SCRATCH_RTDEV]

	for i in "${!_CFG[@]}"; do
		echo "${i}=\"${_CFG[$i]}\"" >> $cfg_path
	done
	unset _CFG
}
