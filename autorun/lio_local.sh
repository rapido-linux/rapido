#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2016, all rights reserved.
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

export_blockdevs="/dev/vda /dev/vdb"

_vm_ar_env_check || exit 1

set -x

# start udevd
ps -eo args | grep -v grep | grep /usr/lib/systemd/systemd-udevd \
	|| /usr/lib/systemd/systemd-udevd --daemon
udevadm settle || _fatal

_vm_ar_configfs_mount

modprobe target_core_mod || _fatal
modprobe target_core_iblock || _fatal
modprobe target_core_file || _fatal
modprobe iscsi_target_mod || _fatal

_vm_ar_dyn_debug_enable

[ -d /sys/kernel/config/target/iscsi ] \
	|| mkdir /sys/kernel/config/target/iscsi || _fatal
mkdir -p /var/target/pr || _fatal

#### iSCSI Discovery authentication information
echo -n 0 > /sys/kernel/config/target/iscsi/discovery_auth/enforce_discovery_auth

#### file backstore
file_path=/lun_filer
file_size_b=1073741824
truncate --size=${file_size_b} $file_path
mkdir -p /sys/kernel/config/target/core/fileio_0/filer || _fatal
echo "fd_dev_name=${file_path}" \
	> /sys/kernel/config/target/core/fileio_0/filer/control || _fatal
echo "fd_dev_size=${file_size_b}" \
	> /sys/kernel/config/target/core/fileio_0/filer/control || _fatal
serial="${file_path//\//_}"	# replace '/' for SCSI serial number
mkdir -p /var/target/alua/tpgs_${serial} || _fatal
echo "$serial" \
	> /sys/kernel/config/target/core/fileio_0/filer/wwn/vpd_unit_serial \
	|| _fatal
echo "1" > /sys/kernel/config/target/core/fileio_0/filer/enable || _fatal
# enable unmap/discard
echo "1" > /sys/kernel/config/target/core/fileio_0/filer/attrib/emulate_tpu \
	|| _fatal

#### iblock + dm-delay backstore
dmdelay_path=/lun_dmdelay
dmdelay_size_b=1073741824
dmdelay_size_blocks=$(($dmdelay_size_b / 512))
dmdelay_ms=6000
# XXX could use zram in guest here, but SLE12SP1 kernel only has it in staging
truncate --size=${dmdelay_size_b} $dmdelay_path || _fatal
dmdelay_loop_dev=`losetup -f` || _fatal
losetup -f $dmdelay_path || _fatal
# setup DM delay device - XXX this needs 95-dm-notify.rules to call
# "dmsetup udevcomplete", otherwise it'll hang indefinitely!
echo "0 $dmdelay_size_blocks delay $dmdelay_loop_dev 0 $dmdelay_ms" \
	| dmsetup create delayed || _fatal
udevadm settle
dmdelay_dev="/dev/dm-0"
mkdir -p /sys/kernel/config/target/core/iblock_0/delayer || _fatal
echo "udev_path=${dmdelay_dev}" \
	> /sys/kernel/config/target/core/iblock_0/delayer/control || _fatal
serial="${dmdelay_dev//\//_}"
mkdir -p /var/target/alua/tpgs_${serial} || _fatal
echo "$serial" \
	> /sys/kernel/config/target/core/iblock_0/delayer/wwn/vpd_unit_serial \
	|| _fatal
echo "1" > /sys/kernel/config/target/core/iblock_0/delayer/enable || _fatal

#### iblock backstores - only if "vda" block device attached
i=1
for iblock_dev in $export_blockdevs; do
	[ -b "$iblock_dev" ] || continue;

	mkdir -p /sys/kernel/config/target/core/iblock_${i}/blocker || _fatal
	echo "udev_path=${iblock_dev}" \
		> /sys/kernel/config/target/core/iblock_${i}/blocker/control \
		|| _fatal
	serial="${iblock_dev//\//_}"
	mkdir -p /var/target/alua/tpgs_${serial} || _fatal
	echo "$serial" \
	 > /sys/kernel/config/target/core/iblock_${i}/blocker/wwn/vpd_unit_serial \
		|| _fatal
	echo "1" > /sys/kernel/config/target/core/iblock_${i}/blocker/enable \
		|| _fatal
	((i++))
done

mkdir /sys/kernel/config/target/iscsi/${TARGET_IQN} || _fatal

for tpgt in tpgt_1 tpgt_2; do
	mkdir /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/ || _fatal

	# file backend as lun 0
	mkdir -p /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/lun/lun_0
	[ $? -eq 0 ] || _fatal
	ln -s /sys/kernel/config/target/core/fileio_0/filer \
		/sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/lun/lun_0/68c6222530
	[ $? -eq 0 ] || _fatal

	# dm-delay backend as lun1
	mkdir -p /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/lun/lun_1
	[ $? -eq 0 ] || _fatal
	ln -s /sys/kernel/config/target/core/iblock_0/delayer \
		/sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/lun/lun_1/68c6222531
	[ $? -eq 0 ] || _fatal

	# /dev/vdX iblock1+ backends as lun2+
	i=1
	for iblock_dev in $export_blockdevs; do
		[ -b "$iblock_dev" ] || continue;

		mkdir -p /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/lun/lun_$((i + 1))
		[ $? -eq 0 ] || _fatal
		ln -s /sys/kernel/config/target/core/iblock_${i}/blocker \
			/sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/lun/lun_$((i + 1))/68c622253$((i + 1))
		[ $? -eq 0 ] || _fatal
		((i++))
	done

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
		# hash IQN and concat first 10 bytes with LUN as ID
		IQN_SHA=`echo $initiator | sha256sum -`
		IQN_SHA=${IQN_SHA:0:9}
		echo "provisioning ACL for $initiator (${IQN_SHA})"

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

		for lun in 0 1; do
			#### iSCSI Initiator LUN ACLs for iSCSI Target Portal Group
			[ -e /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/lun/lun_${lun} ] || continue

			mkdir -p /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/acls/${initiator}/lun_${lun}
			[ $? -eq 0 ] || _fatal
			ln -s /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/lun/lun_${lun} \
				/sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/acls/${initiator}/lun_${lun}/${IQN_SHA}${lun}
			echo 0 > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/acls/${initiator}/lun_${lun}/write_protect
		done

		lun=2
		for iblock_dev in $export_blockdevs; do
			[ -b "$iblock_dev" ] || continue;

			#### iSCSI Initiator LUN ACLs for iSCSI Target Portal Group
			[ -e /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/lun/lun_${lun} ] || continue

			mkdir -p /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/acls/${initiator}/lun_${lun}
			[ $? -eq 0 ] || _fatal
			ln -s /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/lun/lun_${lun} \
				/sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/acls/${initiator}/lun_${lun}/${IQN_SHA}${lun}
			echo 0 > /sys/kernel/config/target/iscsi/${TARGET_IQN}/${tpgt}/acls/${initiator}/lun_${lun}/write_protect
			((lun++))
		done
	done
done

set +x

echo "LUN 0: file backed logical unit, using LIO fileio"
echo "LUN 1: loopback file with 1s dm-delay I/O latency"
lun=2
for iblock_dev in $export_blockdevs; do
	[ -b "$iblock_dev" ] || continue;
	echo "LUN ${lun}: $iblock_dev backed logical unit, using LIO iblock"
	((lun++))
done

# standalone iSCSI target - listen on ports 3260 and 3261 of assigned address
ip link show eth0 | grep $VM1_MAC_ADDR1
if [ $? -eq 0 ]; then
	mkdir /sys/kernel/config/target/iscsi/${TARGET_IQN}/tpgt_1/np/${IP_ADDR1}:3260 \
		|| _fatal
	mkdir /sys/kernel/config/target/iscsi/${TARGET_IQN}/tpgt_2/np/${IP_ADDR1}:3261 \
		|| _fatal

	echo "target ready at: iscsi://${IP_ADDR1}:3260/${TARGET_IQN}/"
	echo "target ready at: iscsi://${IP_ADDR1}:3261/${TARGET_IQN}/"
fi

ip link show eth0 | grep $VM2_MAC_ADDR1
if [ $? -eq 0 ]; then
	mkdir /sys/kernel/config/target/iscsi/${TARGET_IQN}/tpgt_1/np/${IP_ADDR2}:3260 \
		|| _fatal
	mkdir /sys/kernel/config/target/iscsi/${TARGET_IQN}/tpgt_2/np/${IP_ADDR2}:3261 \
		|| _fatal

	echo "target ready at: iscsi://${IP_ADDR2}:3260/${TARGET_IQN}/"
	echo "target ready at: iscsi://${IP_ADDR2}:3261/${TARGET_IQN}/"
fi
echo 1 > /sys/kernel/config/target/iscsi/${TARGET_IQN}/tpgt_1/enable
echo 1 > /sys/kernel/config/target/iscsi/${TARGET_IQN}/tpgt_2/enable
