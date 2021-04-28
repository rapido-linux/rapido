#!/bin/bash
#
# Copyright (C) SUSE LLC 2021, all rights reserved.
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

modprobe cifs
_vm_ar_dyn_debug_enable

if [ -n "$CIFS_UTILS_SRC" ]; then
	ln -s "${CIFS_UTILS_SRC}/mount.cifs" /sbin/
	ln -s "${CIFS_UTILS_SRC}/cifs.upcall" /usr/sbin/
fi

set -x

cat >/etc/request-key.conf <<EOF
create cifs.spnego  * * /usr/sbin/cifs.upcall %k
EOF

cat >/etc/krb5.conf <<EOF
[libdefaults]
dns_lookup_realm = true
dns_lookup_kdc = true
forwardable = true
default_realm = $CIFS_DOMAIN

[logging]
	kdc = FILE:/var/log/krb5/krb5kdc.log
	admin_server = FILE:/var/log/krb5/kadmind.log
	default = FILE:/var/log/krb5/def.log
EOF

# XXX rely on DNS forwarding of CIFS_DOMAIN requests via BR_ADDR
# E.g. dnsmasq --server=/${CIFS_DOMAIN}/${CIFS_SERVER}
cat >/etc/resolv.conf <<EOF
search ${CIFS_DOMAIN,,}
nameserver ${BR_ADDR%/*}
EOF

mkdir -p /run/user/0 /var/log/krb5/ /mnt/cifs
set +x
echo "$CIFS_PW" | kinit "${CIFS_USER}"@"${CIFS_DOMAIN}" || _fatal
klist || _fatal
mount_args="-osec=krb5i,user=${CIFS_USER}"
[ -n "$CIFS_MOUNT_OPTS" ] && mount_args="${mount_args},${CIFS_MOUNT_OPTS}"
set -x

mount -t cifs //"${CIFS_SERVER}"/"${CIFS_SHARE}" /mnt/cifs "$mount_args" \
	|| _fatal
cd /mnt/cifs || _fatal
set +x
