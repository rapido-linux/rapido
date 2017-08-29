#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2017, all rights reserved.
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

filesystem="btrfs"

# use a non-configurable UID/GID for now
cifs_xid="579120"
echo "${CIFS_USER}:x:${cifs_xid}:${cifs_xid}:Samba user:/:/sbin/nologin" \
	>> /etc/passwd
echo "${CIFS_USER}:x:${cifs_xid}:" >> /etc/group

cat /proc/mounts | grep debugfs &> /dev/null
if [ $? -ne 0 ]; then
	mount -t debugfs debugfs /sys/kernel/debug/
fi

cat /proc/mounts | grep configfs &> /dev/null
if [ $? -ne 0 ]; then
	mount -t configfs configfs /sys/kernel/config/
fi

modprobe zram num_devices="1" || _fatal "failed to load zram module"

echo "1G" > /sys/block/zram0/disksize || _fatal "failed to set zram disksize"

mkfs.${filesystem} /dev/zram0 || _fatal "mkfs failed"

mkdir -p /mnt/
mount -t $filesystem /dev/zram0 /mnt/ || _fatal
chmod 777 /mnt/ || _fatal

for i in $DYN_DEBUG_MODULES; do
	echo "module $i +pf" > /sys/kernel/debug/dynamic_debug/control || _fatal
done
for i in $DYN_DEBUG_FILES; do
	echo "file $i +pf" > /sys/kernel/debug/dynamic_debug/control || _fatal
done

mkdir -p /usr/local/samba/var/
mkdir -p /usr/local/samba/etc/
mkdir -p /usr/local/samba/var/lock
mkdir -p /usr/local/samba/private/
mkdir -p /usr/local/samba/lib/
ln -s ${SAMBA_SRC}/bin/modules/vfs/ /usr/local/samba/lib/vfs

smb_conf_vfs=""
if [ "$filesystem" == "btrfs" ]; then
	smb_conf_vfs='vfs objects = btrfs'
fi

cat > /usr/local/samba/etc/smb.conf << EOF
[global]
	workgroup = MYGROUP

[${CIFS_SHARE}]
	path = /mnt
	$smb_conf_vfs
	read only = no
	store dos attributes = yes
EOF

${SAMBA_SRC}/bin/default/source3/smbd/smbd || _fatal

set +x

echo -e "${CIFS_PW}\n${CIFS_PW}\n" \
	| ${SAMBA_SRC}/bin/default/source3/utils/smbpasswd -a $CIFS_USER -s \
				|| _fatal

ip link show eth0 | grep $MAC_ADDR1 &> /dev/null
if [ $? -eq 0 ]; then
	echo "Samba share ready at: //${IP_ADDR1}/${CIFS_SHARE}/"
fi
ip link show eth0 | grep $MAC_ADDR2 &> /dev/null
if [ $? -eq 0 ]; then
	echo "Samba share ready at: //${IP_ADDR2}/${CIFS_SHARE}/"
fi
echo "Log at: /usr/local/samba/var/log.smbd"
