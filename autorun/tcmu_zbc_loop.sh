#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2016-2019, all rights reserved.
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

if [ ! -f /vm_autorun.env ]; then
	echo "Error: autorun scripts must be run from within an initramfs VM"
	exit 1
fi

. /vm_autorun.env

set -x

lio_cfgfs="/sys/kernel/config/target/"
fabric_uuid=$(uuidgen |sed "s#.*-##g")
nexus_uuid=$(uuidgen |sed "s#-##g")
nexus_wwn="naa.${nexus_uuid}"
lu_uuid=$(uuidgen |sed "s#.*-##g")
lu_num=0
lu_name="tcmu_zbc_lu"

tcmu_dev_conf="zbc/model-HM/zsize-128/conv-100@/zbc-backing-file.raw"
tcmu_dev_size="$(( 20 * 1024 * 1024 * 1024 ))"

_vm_ar_configfs_mount

modprobe target_core_user || _fatal "failed to load LIO kernel module"
modprobe tcm_loop || _fatal "failed to load LIO kernel module"

_vm_ar_dyn_debug_enable

echo "$TCMU_RUNNER_SRC" >> /etc/ld.so.conf
export PATH="${PATH}:${TCMU_RUNNER_SRC}"

mkdir -p /etc/tcmu
echo > /etc/tcmu/tcmu.conf

tcmu-runner -d --handler-path $TCMU_RUNNER_SRC &

[ -d $lio_cfgfs ] \
	|| _fatal "$lio_cfgfs not present - LIO kernel modules not loaded?"
mkdir -p ${lio_cfgfs}/core/user_0/${lu_name} \
	||  _fatal "failed to create tcmu backstore"
echo "dev_config=${tcmu_dev_conf},dev_size=${tcmu_dev_size}" \
			> ${lio_cfgfs}/core/user_0/${lu_name}/control \
			|| _fatal "LIO control file I/O failed"
echo 1 > ${lio_cfgfs}/core/user_0/${lu_name}/enable

# loopback fabric
mkdir -p ${lio_cfgfs}/loopback/naa.${fabric_uuid}/tpgt_0/lun/lun_${lu_num} \
	||  _fatal "failed to create LUN for tcmu backstore"
echo ${nexus_wwn} > ${lio_cfgfs}/loopback/naa.${fabric_uuid}/tpgt_0/nexus
ln -s ${lio_cfgfs}/core/user_0/${lu_name}/ \
  ${lio_cfgfs}/loopback/naa.${fabric_uuid}/tpgt_0/lun/lun_${lu_num}/${lu_uuid} \
	|| _fatal "failed to create LUN symlink"

set +x
