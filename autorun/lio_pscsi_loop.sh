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

if [ ! -f /vm_autorun.env ]; then
	echo "Error: autorun scripts must be run from within an initramfs VM"
	exit 1
fi

set -x

lio_cfgfs="/sys/kernel/config/target/"
fabric_uuid=$(uuidgen |sed "s#.*-##g")
nexus_uuid=$(uuidgen |sed "s#-##g")
nexus_wwn="naa.${nexus_uuid}"
lu_uuid=$(uuidgen |sed "s#.*-##g")
lu_num=0
lu_name="pscsi_lu"

_vm_ar_configfs_mount

modprobe virtio_scsi || _fatal "failed to load virtio_scsi kernel module"
modprobe target_core_pscsi || _fatal "failed to load LIO kernel module"
modprobe tcm_loop || _fatal "failed to load LIO kernel module"

_vm_ar_dyn_debug_enable

id_sh=0
id_sc=0
id_st=0
id_sl=0
pscsi_dev="$(lsscsi ${id_sh}:${id_sc}:${id_st}:${id_sl} \
		| awk '{print $NF}')"
[ -n "$pscsi_dev" ] || _fatal "lsscsi failed to locate a local SCSI device"
[ -b "$pscsi_dev" ] || _fatal "lsscsi return \"$pscsi_dev\" is not a blockdev"

[ -d $lio_cfgfs ] \
	|| _fatal "$lio_cfgfs not present - LIO kernel modules not loaded?"
mkdir -p ${lio_cfgfs}/core/pscsi_0/${lu_name} \
	||  _fatal "failed to create pscsi backstore"
echo "scsi_host_id=${id_sh},scsi_channel_id=${id_sc}" \
	> ${lio_cfgfs}/core/pscsi_0/${lu_name}/control \
	|| _fatal "LIO control file I/O failed"
echo "scsi_target_id=${id_st},scsi_lun_id=${id_sl}" \
	> ${lio_cfgfs}/core/pscsi_0/${lu_name}/control \
	|| _fatal "LIO control file I/O failed"
echo $pscsi_dev > /sys/kernel/config/target/core/pscsi_0/${lu_name}/udev_path \
	||  _fatal "failed to configure pscsi backstore"
echo 1 > ${lio_cfgfs}/core/pscsi_0/${lu_name}/enable \
	||  _fatal "failed to configure pscsi backstore"

# loopback fabric
mkdir -p ${lio_cfgfs}/loopback/naa.${fabric_uuid}/tpgt_0/lun/lun_${lu_num} \
	||  _fatal "failed to create LUN for pscsi backstore"
echo ${nexus_wwn} > ${lio_cfgfs}/loopback/naa.${fabric_uuid}/tpgt_0/nexus
ln -s ${lio_cfgfs}/core/pscsi_0/${lu_name}/ \
  ${lio_cfgfs}/loopback/naa.${fabric_uuid}/tpgt_0/lun/lun_${lu_num}/${lu_uuid} \
	|| _fatal "failed to create LUN symlink"

set +x
