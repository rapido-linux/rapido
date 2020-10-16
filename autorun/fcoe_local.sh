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

_vm_ar_env_check || exit 1

set -x

#### start udevd
ps -eo args | grep -v grep | grep /usr/lib/systemd/systemd-udevd \
	|| /usr/lib/systemd/systemd-udevd --daemon

modprobe configfs
_vm_ar_configfs_mount

modprobe target_core_mod || _fatal
modprobe target_core_file || _fatal
modprobe tcm_fc || _fatal
modprobe libfc || _fatal
modprobe fcoe || _fatal

_vm_ar_dyn_debug_enable

# Create the fileio backend
create_fileio() {
	local file_path="$1"
	local file_size_b="$2"

	mkdir -p $(dirname ${file_path})
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
}

create_target() {
	local fcoe_wwn="$1"
	local fileio="/sys/kernel/config/target/core/fileio_0/filer"

	if [ ! -d /sys/kernel/config/target/fc ]; then
		mkdir /sys/kernel/config/target/fc || _fatal
	fi

	tcm_fc=/sys/kernel/config/target/fc/${fcoe_wwn}
	if [ ! -d "$tcm_fc" ] ; then
		mkdir $tcm_fc || _fatal
	fi
	if [ ! -d ${tcm_fc}/tpgt_1 ] ; then
		mkdir ${tcm_fc}/tpgt_1 || _fatal
	fi
	if [ ! -d ${tcm_fc}/tpgt_1/lun/lun_0 ] ; then
		mkdir ${tcm_fc}/tpgt_1/lun/lun_0 || _fatal
		ln -s ${fileio} ${tcm_fc}/tpgt_1/lun/lun_0/mapped_lun
	fi
}

create_fcoe() {
	local fcoe_if="$1"
	local ctlr=""

	echo ${fcoe_if} > /sys/bus/fcoe/ctlr_create

	for c in /sys/bus/fcoe/devices/ctlr_* ; do
		[ -d "$c" ] || continue
		devpath=$(cd -P $c; cd ..; echo $PWD)
		ifname=${devpath##*/}
		if [ "$ifname" = "$fcoe_if" ] ; then
			ctlr="${c##*/}"
			break;
		fi
	done

	echo "vn2vn" > /sys/bus/fcoe/devices/${ctlr}/mode
	echo 1 > /sys/bus/fcoe/devices/${ctlr}/fip_vlan_responder
	echo 1 > /sys/bus/fcoe/devices/${ctlr}/enabled
}

create_acl() {
	target_wwn="$1"
	initiator_wwn="$2"

	tcm_fc="/sys/kernel/config/target/fc/${target_wwn}"
	acl="${tcm_fc}/tpgt_1/acls/${initiator_wwn}"

	if [ ! -d ${acl} ]; then
		mkdir ${acl} || _fatal
	fi

	for l in ${tcm_fc}/tpgt_1/lun/*; do
		[ -d ${l} ] || continue
		lun_acl=${acl}/${l##*/}
		echo "$lun_acl"
		[ -d ${lun_acl} ] || mkdir ${lun_acl} || _fatal
		if [ ! -L ${lun_acl}/mapped_lun ]; then
			ln -s ${l} ${lun_acl}/mapped_lun
		fi
	done
}

find_fcoedev() {
	while [ ! -d /sys/class/fc_remote_ports/rport-* ]; do
		sleep 1
	done
	for rport in /sys/class/fc_remote_ports/rport-*; do
		for target in ${rport}/device/target*/; do
			for d in ${target}/*; do
				hctl="${d##*/}"
				if [ ${hctl} = "fc_transport" \
					  -o ${hctl} = "uevent" \
					  -o ${hctl} = "subsystem" ]; then
					continue;
				fi
				for b in "${target}/${hctl}/block/*"; do
					bdev="$(basename ${b})"
					if readlink -f /sys/block/${bdev} | grep -q "${hctl}"; then
						echo $bdev
					fi
				done
			done
		done
	done
}

ip link show eth0 | grep $VM1_MAC_ADDR1
if [ $? -eq 0 ]; then
	file_path=/var/target/lun
	file_size_b=1073741824
	target_wwn="20:00:$VM1_MAC_ADDR1"
	initiator_wwn="20:00:$MAC_ADDR2"

	create_fcoe "eth0"
	create_fileio ${file_path} ${file_size_b}
	create_target ${target_wwn}
	create_acl ${target_wwn} ${initiator_wwn}

	echo "${file_path} exported via FCoE on $VM1_MAC_ADDR1"
fi

ip link show eth0 | grep $MAC_ADDR2
if [ $? -eq 0 ]; then
	fipvlan -csum vn2vn eth0 || _fatal
	udevadm settle

	bdev=$(find_fcoedev)
	echo "Remote FCoE $VM1_MAC_ADDR1 mapped to /dev/$bdev"
fi

set +x
