#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2019-2023, all rights reserved.

_vm_ar_env_check || exit 1

set -x

_vm_ar_dyn_debug_enable

# use a uid and gid which match the CephFS root owner, so SMB users can perform
# I/O without needing to chmod.
echo "${CIFS_USER}:x:${CEPH_ROOT_INO_UID-0}:${CEPH_ROOT_INO_GID-0}:Samba user:/:/sbin/nologin" \
	>> /etc/passwd
echo "${CIFS_USER}:x:${CEPH_ROOT_INO_GID-0}:" >> /etc/group

mkdir -p /mnt/cephfs
mount -t ceph ${CEPH_MON_ADDRESS_V1}:/ /mnt/cephfs \
	-o name=${CEPH_USER},secret=${CEPH_USER_KEY} || _fatal

cfg_file="/smb.conf"
cat > "$cfg_file" << EOF
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
