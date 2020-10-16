#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2019, all rights reserved.
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

_vm_ar_dyn_debug_enable

export PATH="${SAMBA_SRC}/bin/:${PATH}"

# use a uid and gid which match the CephFS root owner, so SMB users can perform
# I/O without needing to chmod.
echo "${CIFS_USER}:x:${CEPH_ROOT_INO_UID-0}:${CEPH_ROOT_INO_GID-0}:Samba user:/:/sbin/nologin" \
	>> /etc/passwd
echo "${CIFS_USER}:x:${CEPH_ROOT_INO_GID-0}:" >> /etc/group

mkdir -p /mnt/cephfs
mount -t ceph ${CEPH_MON_ADDRESS_V1}:/ /mnt/cephfs \
	-o name=${CEPH_USER},secret=${CEPH_USER_KEY} || _fatal

mkdir -p /usr/local/samba/var/
mkdir -p /usr/local/samba/etc/
mkdir -p /usr/local/samba/var/lock
mkdir -p /usr/local/samba/private/
mkdir -p /usr/local/samba/lib/
ln -s ${SAMBA_SRC}/bin/modules/vfs/ /usr/local/samba/lib/vfs

cat > /usr/local/samba/etc/smb.conf << EOF
[global]
	workgroup = MYGROUP
	load printers = no
	smbd: backgroundqueue = no

[${CIFS_SHARE}]
	path = /mnt/cephfs
	read only = no
	# no flock support
	kernel share modes = no
	# no kernel oplock support
	oplocks = no
EOF

smbd || _fatal

set +x

echo -e "${CIFS_PW}\n${CIFS_PW}\n" \
	| smbpasswd -a $CIFS_USER -s || _fatal

ip link show eth0 | grep $VM1_MAC_ADDR1 &> /dev/null
if [ $? -eq 0 ]; then
	echo "Samba share ready at: //${VM1_IP_ADDR1}/${CIFS_SHARE}/"
fi
ip link show eth0 | grep $VM2_MAC_ADDR1 &> /dev/null
if [ $? -eq 0 ]; then
	echo "Samba share ready at: //${IP_ADDR2}/${CIFS_SHARE}/"
fi
echo "Log at: /usr/local/samba/var/log.smbd"
