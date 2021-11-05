#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2017-2023, all rights reserved.

_vm_ar_env_check || exit 1

set -x

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

cfg_file="/smb.conf"
cat > "$cfg_file" << EOF
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

set +x
_samba_paths_init "$cfg_file"

smbd -s "$cfg_file" || _fatal

echo -e "${CIFS_PW}\n${CIFS_PW}\n" \
	| smbpasswd -c "$cfg_file" -a $CIFS_USER -s || _fatal

pub_ips=()
_vm_ar_ip_addrs_nomask pub_ips
for i in "${pub_ips[@]}"; do
	echo "Samba share ready at: //${i}/${CIFS_SHARE}/"
done
