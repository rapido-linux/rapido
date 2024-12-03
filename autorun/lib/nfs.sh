#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2024, all rights reserved.

_nfs_etc_files_setup() {
	local xid="$1"	# UID/GID
	local user="$2"

	cat >> /etc/passwd <<EOF
rpc:x:464:65534:user for rpcbind:/var/lib/empty:/sbin/nologin
statd:x:463:65533:NFS statd daemon:/var/lib/nfs:/sbin/nologin
${user}:x:${xid}:${xid}:NFS user:/:/sbin/nologin
EOF
	cat >> /etc/group <<EOF
nobody:x:65534:
nogroup:x:65533:nobody
${user}:x:${xid}:
EOF

	cat >> /etc/services <<EOF
nfs	2049/tcp
nfs	2049/udp
sunrpc	111/tcp	rpcbind
sunrpc	111/udp	rpcbind
EOF

	cat > /etc/netconfig <<EOF
udp        tpi_clts      v     inet     udp     -       -
tcp        tpi_cots_ord  v     inet     tcp     -       -
udp6       tpi_clts      v     inet6    udp     -       -
tcp6       tpi_cots_ord  v     inet6    tcp     -       -
rawip      tpi_raw       -     inet      -      -       -
local      tpi_cots_ord  -     loopback  -      -       -
unix       tpi_cots_ord  -     loopback  -      -       -
EOF

	cat > /etc/protocols <<EOF
tcp 6 TCP
udp 17 UDP
EOF

	cat > /etc/nsswitch.conf <<EOF
rpc:	files usrfiles
EOF

	echo > /etc/hosts.allow <<EOF
rpcbind : ALL : ALLOW
EOF
}
