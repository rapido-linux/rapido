#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2017-2023, all rights reserved.

_vm_ar_env_check || exit 1

set -x

modprobe zram num_devices="1" || _fatal "failed to load zram module"
_vm_ar_dyn_debug_enable

# use a non-configurable UID/GID for now
cifs_xid="579120"
echo "${CIFS_USER}:x:${cifs_xid}:${cifs_xid}:Samba user:/:/sbin/nologin" \
	>> /etc/passwd
echo "${CIFS_USER}:x:${cifs_xid}:" >> /etc/group

echo "${FSTESTS_ZRAM_SIZE:-1G}" > /sys/block/zram0/disksize \
	|| _fatal "failed to set zram disksize"
mkfs.xfs /dev/zram0 || _fatal "mkfs failed"
mkdir -p /mnt/
mount -t xfs /dev/zram0 /mnt/ || _fatal
chmod 777 /mnt/ || _fatal

cfg_file="/smb.conf"
cat > "$cfg_file" << EOF
[global]
	workgroup = MYGROUP
	load printers = no
	smbd: backgroundqueue = no
[${CIFS_SHARE}]
	path = /mnt
	read only = no
	store dos attributes = yes
	comment = XFS backed share
EOF

set +x
_samba_paths_init "$cfg_file"
smbd -s "$cfg_file" || _fatal
echo -e "${CIFS_PW}\n${CIFS_PW}\n" \
	| smbpasswd -c "$cfg_file" -a $CIFS_USER -s || _fatal

pub_ips=()
_vm_ar_ip_addrs_nomask pub_ips
for i in "${pub_ips[@]}"; do
	echo "XFS backed Samba share ready at: //${i}/${CIFS_SHARE}/"
done
