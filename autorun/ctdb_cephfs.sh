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

. /vm_ceph.env || _fatal

_vm_ar_dyn_debug_enable

export PATH="${SAMBA_SRC}/bin/:${PATH}"

# use a uid and gid which match the CephFS root owner, so SMB users can perform
# I/O without needing to chmod.
echo "${CIFS_USER}:x:${CEPH_ROOT_INO_UID-0}:${CEPH_ROOT_INO_GID-0}:Samba user:/:/sbin/nologin" \
	>> /etc/passwd
echo "${CIFS_USER}:x:${CEPH_ROOT_INO_GID-0}:" >> /etc/group

sed -i "s#keyring = .*#keyring = /etc/ceph/keyring#g; \
	s#admin socket = .*##g; \
	s#run dir = .*#run dir = /var/run/#g; \
	s#log file = .*#log file = /var/log/\$name.\$pid.log#g" \
	/etc/ceph/ceph.conf

mkdir -p /usr/local/etc/ctdb
mkdir -p /usr/local/libexec
mkdir -p /usr/local/bin
mkdir -p /usr/local/samba/etc/ctdb
mkdir -p /usr/local/samba/var/log
mkdir -p /usr/local/samba/var/lock
mkdir -p /usr/local/samba/private
mkdir -p /usr/local/samba/lib
mkdir -p /usr/local/samba/var/lib/ctdb/state
mkdir -p /usr/local/samba/var/lib/ctdb/persistent
mkdir -p /usr/local/samba/var/lib/ctdb/volatile
mkdir -p /usr/local/samba/var/run/ctdb
mkdir -p /etc/sysconfig
ln -s ${SAMBA_SRC}/bin/modules/vfs/ /usr/local/samba/lib/vfs

# XXX these paths are a mess
ln -s ${SAMBA_SRC}/bin/default /usr/local/samba/libexec
ln -s ${SAMBA_SRC}/bin/default/ctdb /usr/local/libexec/ctdb
# renamed with Samba 4.9 events.d -> event
ctdb_events_dir="$(ls -d ${SAMBA_SRC}/ctdb/config/events*)"
ln -s "$ctdb_events_dir" /usr/local/samba/etc/ctdb/

# FIXME: 00.ctdb.script calls CTDB, which default to the path below
ln -s ${SAMBA_SRC}/bin/default/ctdb/ctdb /usr/local/bin/ctdb
# 00.ctdb.script uses $PATH for tdbtool

# disable all event scripts by default. ".script" suffix is for Samba 4.9+
for es in $(find "$ctdb_events_dir"); do
	case "${es##*/}" in
		"00.ctdb"|"00.ctdb.script")
			chmod 755 "$es" ;;
		*)
			chmod 644 "$es" ;;
	esac
done

# echo "CTDB=\"${SAMBA_SRC}/bin/default/ctdb/ctdb\"" > /etc/sysconfig/ctdb || _fatal

cat > /usr/local/samba/etc/smb.conf << EOF
[global]
	workgroup = MYGROUP
	clustering = yes
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

# FIXME this doesn't appear to be read
cat > /usr/local/etc/ctdb/ctdbd.conf << EOF
	# CTDB_SAMBA_SKIP_SHARE_CHECK is only needed if the samba
	# 50.samba.script is enabled alongside a vfs_ceph backed share
	CTDB_SAMBA_SKIP_SHARE_CHECK=yes
	# \$CTDB used by 00.ctdb.script
	CTDB=\"${SAMBA_SRC}/bin/default/ctdb/ctdb\"
EOF

reclock_usr="client.${CEPH_USER}"
reclock_bin="${SAMBA_SRC}/bin/default/ctdb/ctdb_mutex_ceph_rados_helper"
reclock_pool="cephfs_metadata_a"	# vstart default CephFS metadata pool
reclock_obj="ctdb-mutex"
cat > /usr/local/samba/etc/ctdb/ctdb.conf << EOF
[cluster]
    recovery lock = !${reclock_bin} ceph $reclock_usr $reclock_pool $reclock_obj
EOF

echo $IP_ADDR1 >> /usr/local/samba/etc/ctdb/nodes
echo $IP_ADDR2 >> /usr/local/samba/etc/ctdb/nodes

ctdbd || _fatal

echo "ctdbd started, waiting for ctdb to become OK..."
ctdb_wait_timeout_s="60"
for ((i=1; i <= $ctdb_wait_timeout_s; i++)); do
	cstat="$(ctdb status | grep 'THIS NODE')" || _fatal
	echo "$cstat"
	if [ -z "${cstat#*OK (THIS NODE)}" ]; then
		break
	fi
	sleep 1
done

[ $i -lt $ctdb_wait_timeout_s ] || _fatal "timeout"

echo "Starting smbd..."
smbd || _fatal

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
echo "Logs at /usr/local/samba/var/log/log.ctdb & /usr/local/samba/var/log.smbd"
