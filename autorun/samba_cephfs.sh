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

_vm_ar_env_check || exit 1

set -x

export PATH="${SAMBA_SRC}/bin/:${PATH}"

# use a uid and gid which match the CephFS root owner, so SMB users can perform
# I/O without needing to chmod.
echo "${CIFS_USER}:x:${CEPH_ROOT_INO_UID-0}:${CEPH_ROOT_INO_GID-0}:Samba user:/:/sbin/nologin" \
	>> /etc/passwd
echo "${CIFS_USER}:x:${CEPH_ROOT_INO_GID-0}:" >> /etc/group

_vm_ar_dyn_debug_enable

sed -i "s#keyring = .*#keyring = /etc/ceph/keyring#g; \
	s#admin socket = .*##g; \
	s#run dir = .*#run dir = /var/run/#g; \
	s#log file = .*#log file = /var/log/\$name.\$pid.log#g" \
	/etc/ceph/ceph.conf

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
	path = /
	vfs objects = ceph
	ceph: config_file = /etc/ceph/ceph.conf
	ceph: user_id = $CEPH_USER
	read only = no
	# no vfs_ceph flock support - "kernel" is confusing here
	kernel share modes = no
	# no vfs_ceph lease delegation support
	oplocks = no
EOF

smbd || _fatal

set +x

echo -e "${CIFS_PW}\n${CIFS_PW}\n" \
	| smbpasswd -a $CIFS_USER -s || _fatal

ip link show eth0 | grep $MAC_ADDR1 &> /dev/null
if [ $? -eq 0 ]; then
	echo "Samba share ready at: //${IP_ADDR1}/${CIFS_SHARE}/"
fi
ip link show eth0 | grep $MAC_ADDR2 &> /dev/null
if [ $? -eq 0 ]; then
	echo "Samba share ready at: //${IP_ADDR2}/${CIFS_SHARE}/"
fi
echo "Log at: /usr/local/samba/var/log.smbd"
