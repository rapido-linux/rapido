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

# same as _fstests_devs_provision() except a SCRATCH_DEV* wildcard is used to
# fill SCRATCH_DEV_POOL. Any devices matching the wildcard will be added to the
# SCRATCH_DEV_POOL list. If none are present then five zram devices will be
# provisioned and used instead.
_fstests_devs_pool_provision() {
	local cfg_path="$1"
	local i ser devp
	declare -A _CFG=(["SCRATCH_LOGDEV"]="" ["SCRATCH_RTDEV"]=""
			 ["TEST_DEV"]="")
	declare -a _POOL=()

	for i in $(ls /sys/block); do
		ser="$(cat /sys/block/${i}/serial 2>/dev/null)" || continue
		devp="/dev/${i}"
		[[ -v "_CFG[$ser]" ]] && _CFG[$ser]="$devp"
		[[ $ser == "SCRATCH_DEV"* && -b "$devp" ]] && _POOL+=("$devp")
	done

	[ -b "${_CFG[TEST_DEV]}" ] || _fstests_devs_zram_setup TEST_DEV
	[ -b "${_CFG[SCRATCH_LOGDEV]}" ] || unset _CFG[SCRATCH_LOGDEV]
	[ -b "${_CFG[SCRATCH_RTDEV]}" ] || unset _CFG[SCRATCH_RTDEV]
	if [ ${#_POOL[@]} -eq 0 ]; then
		for ((i = 0; i < 5; i++)); do
			_fstests_devs_zram_setup POOL_DEV
			_POOL+=("${_CFG[POOL_DEV]}")
		done
		unset _CFG[POOL_DEV]
	fi
	_CFG[SCRATCH_DEV_POOL]="${_POOL[@]}"

	for i in "${!_CFG[@]}"; do
		echo "${i}=\"${_CFG[$i]}\"" >> $cfg_path
	done
	unset _CFG _POOL
}
