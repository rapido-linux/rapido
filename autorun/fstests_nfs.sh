#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2022, all rights reserved.

_vm_ar_env_check || exit 1

modprobe nfs
_vm_ar_dyn_debug_enable
_vm_ar_hosts_create

_fstests_users_groups_provision

[[ -n $NFS_SERVER && -n $NFS_SHARE ]] \
	|| _fatal "NFS_SERVER and NFS_SHARE must be set in rapido.conf"
[[ -n $NFS_MOUNT_OPTS ]] && mount_args="-o${NFS_MOUNT_OPTS}"

# use a non-configurable UID/GID for now
nfs_xid="579121"
nfs_user="nfsuser"
cat >> /etc/passwd <<EOF
rpc:x:464:65534:user for rpcbind:/var/lib/empty:/sbin/nologin
statd:x:463:65533:NFS statd daemon:/var/lib/nfs:/sbin/nologin
${nfs_user}:x:${nfs_xid}:${nfs_xid}:NFS user:/:/sbin/nologin
EOF
cat >> /etc/group <<EOF
nobody:x:65534:
nogroup:x:65533:nobody
${nfs_user}:x:${nfs_xid}:
EOF

cat >> /etc/services <<EOF
nfs	2049/tcp
nfs	2049/udp
sunrpc	111/tcp	rpcbind
sunrpc	111/udp	rpcbind
EOF

cat >  /etc/netconfig <<EOF
udp        tpi_clts      v     inet     udp     -       -
tcp        tpi_cots_ord  v     inet     tcp     -       -
udp6       tpi_clts      v     inet6    udp     -       -
tcp6       tpi_cots_ord  v     inet6    tcp     -       -
rawip      tpi_raw       -     inet      -      -       -
local      tpi_cots_ord  -     loopback  -      -       -
unix       tpi_cots_ord  -     loopback  -      -       -
EOF

cat >> /etc/nsswitch.conf <<EOF
rpc:	files usrfiles
EOF

echo > /etc/hosts.allow <<EOF
rpcbind : ALL : ALLOW
EOF

set -x

mkdir -p /var/lib/nfs/sm /mnt/test
rpcbind || _fatal
rpc.statd || _fatal
rpcinfo "$NFS_SERVER"
mount -v -t nfs $mount_args "${NFS_SERVER}:/${NFS_SHARE}" /mnt/test || _fatal
cd /mnt/test || _fatal
[[ -n $FSTESTS_SRC ]] || _fatal "FSTESTS_SRC unset"
[[ -d $FSTESTS_SRC ]] || _fatal "$FSTESTS_SRC missing"

cfg="${FSTESTS_SRC}/configs/$(hostname -s).config"
cat > $cfg << EOF
MODULAR=0
TEST_DIR=/mnt/test
TEST_DEV=${NFS_SERVER}:/${NFS_SHARE}
TEST_FS_MOUNT_OPTS="$mount_args"
FSTYP="nfs"
USE_KMEMLEAK=yes
EOF

set +x

cd "$FSTESTS_SRC" || _fatal
[[ -n $FSTESTS_AUTORUN_CMD ]] && eval "$FSTESTS_AUTORUN_CMD"
