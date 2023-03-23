#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2017-2023, all rights reserved.

_vm_ar_env_check || exit 1

set -x
modprobe zram num_devices="1" || _fatal "failed to load zram module"
modprobe ksmbd
_vm_ar_dyn_debug_enable

# ksmbd utilities are currently all symlinks to ksmbd.tools
for i in ksmbd.addshare ksmbd.adduser ksmbd.control ksmbd.mountd; do
	p="${PATH}:/usr/libexec:/sbin:/usr/sbin"
        if [ -n "$KSMBD_TOOLS_SRC" ]; then
		p="${KSMBD_TOOLS_SRC}/tools"
        fi
	ln -s $(PATH=$p type -P ksmbd.tools) /sbin/${i}
done

# use a non-configurable UID/GID for now
cifs_xid="579120"
echo "${CIFS_USER}:x:${cifs_xid}:${cifs_xid}:Samba user:/:/sbin/nologin" \
	>> /etc/passwd
echo "${CIFS_USER}:x:${cifs_xid}:" >> /etc/group

echo "${FSTESTS_ZRAM_SIZE:-1G}" > /sys/block/zram0/disksize \
	|| _fatal "failed to set zram disksize"
mkfs.btrfs /dev/zram0 || _fatal "mkfs failed"
mkdir -p /mnt/ /etc/ksmbd
mount -t btrfs /dev/zram0 /mnt/ || _fatal
chmod 777 /mnt/ || _fatal

cfg_file="/etc/ksmbd/ksmbd.conf"
users_db="/etc/ksmbd/ksmbdpwd.db"

cat > "$cfg_file" << EOF
[global]
	workgroup = MYGROUP

[${CIFS_SHARE}]
	path = /mnt
	read only = no
	store dos attributes = yes
EOF

ksmbd.mountd -c "$cfg_file" -u "$users_db" \
	|| _fatal "failed to start ksmbd.mountd"
set +x
echo -e "${CIFS_PW}\n${CIFS_PW}\n" \
	| ksmbd.adduser -a "$CIFS_USER" -c "$cfg_file" -i "$users_db" \
		|| _fatal "failed to add ksmbd user"

pub_ips=()
_vm_ar_ip_addrs_nomask pub_ips
for i in "${pub_ips[@]}"; do
	echo "ksmbd share ready at: //${i}/${CIFS_SHARE}/"
done
