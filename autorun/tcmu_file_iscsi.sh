#!/bin/bash
#
# Copyright (C) SUSE LLC 2020, all rights reserved.
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
lu_name="tcmu_file"
tcmu_dev_conf="file/${lu_name}.img"
tcmu_dev_size="$(( 1024 * 1024 * 1024 ))"

ps -eo args | grep -v grep | grep /usr/lib/systemd/systemd-udevd \
	|| /usr/lib/systemd/systemd-udevd --daemon

_vm_ar_configfs_mount

modprobe target_core_user || _fatal "failed to load LIO kernel module"

_vm_ar_dyn_debug_enable

echo "$TCMU_RUNNER_SRC" >> /etc/ld.so.conf
export PATH="${PATH}:${TCMU_RUNNER_SRC}"

mkdir -p /etc/tcmu
echo > /etc/tcmu/tcmu.conf

truncate --size $tcmu_dev_size "/${lu_name}.img"
tcmu-runner -d --handler-path $TCMU_RUNNER_SRC &
sleep 1	# wait for tcmu-runner to start

tcmu_backstore_setup() {
	mkdir -p ${lio_cfgfs}/core/user_0/${lu_name} \
		||  _fatal "failed to create tcmu backstore"
	pushd ${lio_cfgfs}/core/user_0/${lu_name} || _fatal
	uuidgen -r > ./wwn/vpd_unit_serial || _fatal
	echo "dev_config=${tcmu_dev_conf},dev_size=${tcmu_dev_size}" \
		> ./control || _fatal "LIO control file I/O failed"
	echo 1 > ./enable || _fatal
	popd
}

iscsi_setup() {
	local i tpgt="tpgt_1"
	mkdir -p ${lio_cfgfs}/iscsi/${TARGET_IQN}/${tpgt} || _fatal
	pushd ${lio_cfgfs}/iscsi/${TARGET_IQN}/${tpgt} || _fatal

	mkdir ./lun/lun_0 || _fatal
	ln -s ${lio_cfgfs}/core/user_0/${lu_name} ./lun/lun_0/ || _fatal
	echo 0 > ./attrib/authentication

	for i in $INITIATOR_IQNS; do
		mkdir -p ./acls/${i} || _fatal
		mkdir ./acls/${i}/lun_0 || _fatal
		echo 0 > ./acls/${i}/lun_0/write_protect || _fatal
		ln -s ./lun/lun_0 ./acls/${i}/lun_0/ || _fatal
	done

	ip link show eth0 | grep $MAC_ADDR1
	if [ $? -eq 0 ]; then
		mkdir ./np/${IP_ADDR1}:3260 || _fatal
		echo "target ready at: iscsi://${IP_ADDR1}:3260/${TARGET_IQN}/"
	fi
	ip link show eth0 | grep $MAC_ADDR2
	if [ $? -eq 0 ]; then
		mkdir ./np/${IP_ADDR2}:3260 || _fatal
		echo "target ready at: iscsi://${IP_ADDR2}:3260/${TARGET_IQN}/"
	fi
	echo 1 > ./enable
	popd
}

[ -d $lio_cfgfs ] \
	|| _fatal "$lio_cfgfs not present - LIO kernel modules not loaded?"
tcmu_backstore_setup
set +x
iscsi_setup
