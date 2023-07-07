#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2023, all rights reserved.

_vm_ar_env_check || exit 1

set -x

fabric_uuid=$(uuidgen |sed "s#.*-##g")
nexus_uuid=$(uuidgen |sed "s#-##g")
nexus_wwn="naa.${nexus_uuid}"
lu_uuid=$(uuidgen |sed "s#.*-##g")
lu_num=0

_ceph_rbd_map
_vm_ar_configfs_mount

modprobe target_core_mod || _fatal
modprobe target_core_rbd || _fatal

_vm_ar_dyn_debug_enable

# this path is reliant on the rbd udev rule to setup the link
CEPH_RBD_DEV=/dev/rbd/${CEPH_RBD_POOL}/${CEPH_RBD_IMAGE}
[ -L $CEPH_RBD_DEV ] || _fatal

rbd_backstore="/sys/kernel/config/target/core/rbd_0/rbder"
mkdir -p "$rbd_backstore" || _fatal
echo "udev_path=${CEPH_RBD_DEV}" > "$rbd_backstore"/control || _fatal
rbd_features=$(cat /sys/devices/rbd/0/features)
# By default LIO advertises the erroneous emulate_legacy_capacity=1 RBD
# off-by-one capacity, but this needs to be disabled for
# RBD_FEATURE_OBJECT_MAP (1ULL<<3)
if (($rbd_features & 0x08 == 0x08)); then
	echo 0 > "$rbd_backstore"/attrib/emulate_legacy_capacity || _fatal
	echo "emulate_legacy_capacity explicitly disabled"
else
	printf "emulate_legacy_capacity left as default: %s\n" \
	  $(cat "$rbd_backstore"/attrib/emulate_legacy_capacity)
fi
serial="${CEPH_RBD_DEV//\//_}"	# replace '/' for SCSI serial number
echo "$serial" > "$rbd_backstore"/wwn/vpd_unit_serial || _fatal
echo "1" > "$rbd_backstore"/enable || _fatal
# needs to be done after enable, as target_configure_device() resets it
echo "SUSE" > "$rbd_backstore"/wwn/vendor_id || _fatal
# enable unmap/discard
echo "1" > "$rbd_backstore"/attrib/emulate_tpu || _fatal

# loopback fabric
loopback_tpg="/sys/kernel/config/target/loopback/naa.${fabric_uuid}/tpgt_0"
mkdir -p "${loopback_tpg}/lun/lun_${lu_num}" \
	||  _fatal "failed to create LUN for loopback fabric"
echo "$nexus_wwn" > "${loopback_tpg}/nexus"
ln -s "$rbd_backstore" "${loopback_tpg}/lun/lun_${lu_num}/${lu_uuid}" \
	|| _fatal "failed to create LUN symlink"
udevadm wait -t 60 /dev/sda || _fatal

set +x

echo "$CEPH_RBD_DEV successfully configured as loopback SCSI device"
