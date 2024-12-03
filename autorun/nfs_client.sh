#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2022, all rights reserved.

_vm_ar_env_check || exit 1

modprobe nfs
_vm_ar_dyn_debug_enable
_vm_ar_hosts_create

[[ -n $NFS_SERVER && -n $NFS_SHARE ]] \
	|| _fatal "NFS_SERVER and NFS_SHARE must be set in rapido.conf"
[[ -n $NFS_MOUNT_OPTS ]] && mount_args="-o${NFS_MOUNT_OPTS}"

# use a non-configurable UID/GID for now
nfs_xid="579121"
nfs_user="nfsuser"
_nfs_etc_files_setup "$nfs_xid" "$nfs_user"

set -x

mkdir -p /var/lib/nfs/sm /mnt/nfs
rpcbind || _fatal
rpc.statd || _fatal
rpcinfo "$NFS_SERVER"
mount -v -t nfs $mount_args "${NFS_SERVER}:/${NFS_SHARE}" /mnt/nfs || _fatal
cd /mnt/nfs || _fatal
set +x
