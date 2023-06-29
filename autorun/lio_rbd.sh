#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2016, all rights reserved.

_vm_ar_env_check || exit 1

set -x

_ceph_rbd_map

# this path is reliant on the rbd udev rule to setup the link
CEPH_RBD_DEV=/dev/rbd/${CEPH_RBD_POOL}/${CEPH_RBD_IMAGE}
[ -L $CEPH_RBD_DEV ] || _fatal

_vm_ar_configfs_mount

modprobe target_core_mod || _fatal
modprobe target_core_rbd || _fatal

_vm_ar_dyn_debug_enable

[ -d /sys/kernel/config/target/iscsi ] \
	|| mkdir /sys/kernel/config/target/iscsi || _fatal
# no need to create PR state directory, as it's stored in RADOS

# iSCSI Discovery authentication information
echo -n 0 > /sys/kernel/config/target/iscsi/discovery_auth/enforce_discovery_auth

# rbd backed block device
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
mkdir -p /var/target/alua/tpgs_${serial} || _fatal
echo "$serial" > "$rbd_backstore"/wwn/vpd_unit_serial || _fatal
echo "1" > "$rbd_backstore"/enable || _fatal
# needs to be done after enable, as target_configure_device() resets it
echo "SUSE" > "$rbd_backstore"/wwn/vendor_id || _fatal
# enable unmap/discard
echo "1" > "$rbd_backstore"/attrib/emulate_tpu || _fatal

mkdir /sys/kernel/config/target/iscsi/${TARGET_IQN} || _fatal

for tpgt in tpgt_1 tpgt_2; do
	mkdir /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/ || _fatal

	# rbd dev as lun 0
	mkdir -p /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/lun/lun_0
	[ $? -eq 0 ] || _fatal
	ln -s "$rbd_backstore" /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/lun/lun_0/68c6222530
	[ $? -eq 0 ] || _fatal

	#### Network portals for iSCSI Target Portal Group
	#### iSCSI Target Ports
	#### Attributes for iSCSI Target Portal Group
	echo 0 > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/attrib/t10_pi
	echo 0 > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/attrib/default_erl
	echo 1 > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/attrib/demo_mode_discovery
	echo 0 > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/attrib/prod_mode_write_protect
	echo 1 > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/attrib/demo_mode_write_protect
	echo 0 > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/attrib/cache_dynamic_acls
	echo 64 > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/attrib/default_cmdsn_depth
	echo 1 > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/attrib/generate_node_acls
	echo 2 > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/attrib/netif_timeout
	echo 15 > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/attrib/login_timeout
	echo 0 > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/attrib/tpg_enabled_sendtargets
	# disable auth
	echo 0 > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/attrib/authentication

	#### authentication for iSCSI Target Portal Group
	#### Parameters for iSCSI Target Portal Group
	echo "2048~65535" > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/param/OFMarkInt
	echo "2048~65535" > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/param/IFMarkInt
	echo "No" > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/param/OFMarker
	echo "No" > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/param/IFMarker
	echo "0" > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/param/ErrorRecoveryLevel
	echo "Yes" > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/param/DataSequenceInOrder
	echo "Yes" > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/param/DataPDUInOrder
	echo "1" > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/param/MaxOutstandingR2T
	echo "20" > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/param/DefaultTime2Retain
	echo "2" > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/param/DefaultTime2Wait
	echo "65536" > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/param/FirstBurstLength
	echo "262144" > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/param/MaxBurstLength
	echo "262144" > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/param/MaxXmitDataSegmentLength
	echo "8192" > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/param/MaxRecvDataSegmentLength
	echo "Yes" > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/param/ImmediateData
	echo "Yes" > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/param/InitialR2T
	echo "LIO Target" > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/param/TargetAlias
	echo "1" > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/param/MaxConnections
	echo "CRC32C,None" > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/param/DataDigest
	echo "CRC32C,None" > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/param/HeaderDigest
	echo "CHAP,None" > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/param/AuthMethod

	for initiator in $INITIATOR_IQNS; do
		# hash IQN and concat first 10 bytes with LUN as ID (XXX serial number?)
		IQN_SHA=`echo $initiator | sha256sum -`
		IQN_SHA=${IQN_SHA:0:9}
		echo "provisioning ACL for $initiator with lun 0 (${IQN_SHA})"

		#### iSCSI Initiator ACLs for iSCSI Target Portal Group
		mkdir -p /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/acls/${initiator}
		[ $? -eq 0 ] || _fatal
		echo 64 > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/acls/${initiator}/cmdsn_depth
		#### iSCSI Initiator ACL authentication information
		#### iSCSI Initiator ACL TPG attributes
		echo 0 > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/acls/${initiator}/attrib/random_r2t_offsets
		echo 0 > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/acls/${initiator}/attrib/random_datain_seq_offsets
		echo 0 > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/acls/${initiator}/attrib/random_datain_pdu_offsets
		echo 30 > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/acls/${initiator}/attrib/nopin_response_timeout
		echo 15 > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/acls/${initiator}/attrib/nopin_timeout
		echo 0 > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/acls/${initiator}/attrib/default_erl
		echo 5 > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/acls/${initiator}/attrib/dataout_timeout_retries
		echo 3 > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/acls/${initiator}/attrib/dataout_timeout

		for lun in 0; do
			#### iSCSI Initiator LUN ACLs for iSCSI Target Portal Group
			mkdir -p /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/acls/${initiator}/lun_${lun}
			[ $? -eq 0 ] || _fatal
			ln -s /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/acls/${initiator}/lun_${lun}/../../../../../../../target/iscsi/${TARGET_IQN}/${tpgt}/lun/lun_${lun} /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/acls/${initiator}/lun_${lun}/${IQN_SHA}${lun}
			echo 0 > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/acls/${initiator}/lun_${lun}/write_protect
		done
	done
done

set +x

pub_ips=()
_vm_ar_ip_addrs_nomask pub_ips
# build a magic regexp which matches against any locally assigned IP address
pub_ips_re="^($(IFS=\|; echo "${pub_ips[*]}"))$"

# create a portal for the first configured IP address for VMs 1 and 2
cd "/sys/kernel/config/target/iscsi/${TARGET_IQN}"
for i in 1 2; do
	cfg_ips=()
	_vm_ar_cfg_ips_nomask "$i" cfg_ips
	(( ${#cfg_ips[@]} > 0 )) || _fatal "vm${i} lacks IP address config"
	mkdir "tpgt_${i}/np/${cfg_ips[0]}:3260" || _fatal

	# Enable portal if address is a local IP. Non-local portals will remain
	# disabled, but still be advertised (tpg_enabled_sendtargets=0).
	[[ ${cfg_ips[0]} =~ $pub_ips_re ]] || continue
	echo 1 > "tpgt_${i}/enable" || _fatal
	echo "target ready at: iscsi://${cfg_ips[0]}:3260/${TARGET_IQN}/"
done
cd /
