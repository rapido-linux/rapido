#!/bin/bash
#
# Copyright (C) SUSE LLC 2021, all rights reserved.
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

_vm_ar_env_check || exit 1

set -x

lio_cfgfs="/sys/kernel/config/target/"
lu_name="lu_file"
dev_size="$(( 1024 * 1024 * 1024 ))"

ps -eo args | grep -v grep | grep /usr/lib/systemd/systemd-udevd \
	|| /usr/lib/systemd/systemd-udevd --daemon

_vm_ar_configfs_mount

modprobe target_core_file || _fatal
modprobe iscsi_target_mod || _fatal

_vm_ar_dyn_debug_enable

backstore_setup() {
	mkdir -p ${lio_cfgfs}/core/fileio_0/${lu_name} \
		||  _fatal "failed to create backstore"
	pushd ${lio_cfgfs}/core/fileio_0/${lu_name} || _fatal
	uuidgen -r > ./wwn/vpd_unit_serial || _fatal
	echo "fd_dev_name=/${lu_name}.img,fd_dev_size=${dev_size}" \
		> ./control || _fatal "LIO control file I/O failed"
	echo 1 > ./enable || _fatal
	popd
}

iscsi_setup() {
	local i tpgt="tpgt_1"
	mkdir -p ${lio_cfgfs}/iscsi/${TARGET_IQN}/${tpgt} || _fatal
	pushd ${lio_cfgfs}/iscsi/${TARGET_IQN}/${tpgt} || _fatal

	mkdir ./lun/lun_0 || _fatal
	ln -s ${lio_cfgfs}/core/fileio_0/${lu_name} ./lun/lun_0/ || _fatal
	echo 0 > ./attrib/authentication

	for i in $INITIATOR_IQNS; do
		mkdir -p ./acls/${i} || _fatal
		mkdir ./acls/${i}/lun_0 || _fatal
		echo 0 > ./acls/${i}/lun_0/write_protect || _fatal
		ln -s ./lun/lun_0 ./acls/${i}/lun_0/ || _fatal
	done

	local pub_ips=()
	_vm_ar_ip_addrs_nomask pub_ips
	if (( ${#pub_ips[@]} > 0 )); then
		mkdir "./np/${pub_ips[0]}:3260" || _fatal
		echo "target ready at: iscsi://${pub_ips[0]}:3260/${TARGET_IQN}/"
	fi
	echo 1 > ./enable
	popd
}

alua_lba_dependent_setup() {
	local dev_blocks="$(($dev_size / 512))"
	# ALUA_ACCESS_STATE_ACTIVE_OPTIMIZED     0x0
	# ALUA_ACCESS_STATE_ACTIVE_NON_OPTIMIZED 0x1
	# ALUA_ACCESS_STATE_STANDBY              0x2
	# ALUA_ACCESS_STATE_UNAVAILABLE          0x3
	# ALUA_ACCESS_STATE_LBA_DEPENDENT        0x4
	# ALUA_ACCESS_STATE_OFFLINE              0xe
	# ALUA_ACCESS_STATE_TRANSITION           0xf

	# the ALUA lba map is confusingly not under lu/alua/
	pushd ${lio_cfgfs}/core/fileio_0/lu_file || _fatal

	# syntax here is:
	#   segment_size segment_multiplier
	#   start_lba end_lba pgid alua_state
	#   ...
	#
	# where alua_state is one of:
	#   'O': ACTIVE_OPTIMIZED
	#   'A': ACTIVE_NON_OPTIMIZED
	#   'S': STANDBY
	#   'U': UNAVAILABLE
	# start with a single optimized range which spans the entire lu
	echo -e "512 1\n0 $((dev_blocks - 1)) 0:O\n" > lba_map

	pushd alua/default_tg_pt_gp || _fatal

	# TPGS_IMPLICIT_ALUA. See core_alua_store_access_type() for magic val
	echo 1 > alua_access_type || _fatal

	# configure lba dependent 
	echo 4 > alua_access_state

	popd # remain in lu_file

	echo -e "Current lba_map is:\n$(cat lba_map)"
cat <<EOF
To switch lba_map range(s) from optimized to unavailable, run:
  sed "s#:O#:U#" lba_map > lba_map
EOF
}

[ -d $lio_cfgfs ] \
	|| _fatal "$lio_cfgfs not present - LIO kernel modules not loaded?"
truncate --size $dev_size "/${lu_name}.img"
backstore_setup
iscsi_setup
set +x
alua_lba_dependent_setup
