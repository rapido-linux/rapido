#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2022, all rights reserved.

_vm_ar_env_check || exit 1

modprobe zram num_devices="1" || _fatal "failed to load zram module"
modprobe nfsd || _fatal "failed to load nfsd module"
_vm_ar_dyn_debug_enable
_vm_ar_hosts_create

[[ -n $NFS_SHARE ]] || _fatal "NFS_SHARE must be set in rapido.conf"

# use a non-configurable UID/GID for now
nfs_xid="579121"
nfs_user="nfsuser"
_nfs_etc_files_setup "$nfs_xid" "$nfs_user"

# may be used as an fstests target, so use FSTESTS_ZRAM_SIZE
echo "${FSTESTS_ZRAM_SIZE:-1G}" > /sys/block/zram0/disksize \
	|| _fatal "failed to set zram disksize"
mkfs.btrfs /dev/zram0 || _fatal "mkfs failed"

nfs_share="$(realpath -m "$NFS_SHARE")"
mkdir -p "$nfs_share" "/var/lib/nfs"
mount -t btrfs /dev/zram0 "$nfs_share" || _fatal
chmod 777 "$nfs_share" || _fatal

cat > /etc/exports <<EOF
$nfs_share  *(rw,subtree_check,all_squash,anonuid=${nfs_xid},anongid=${nfs_xid})
EOF

# rpcbind uses /dev/log for logging
#setsid --fork nc -lUk /dev/log > /var/log/stuff.log

set -x

rpcbind || _fatal "rpcbind failed to start"
rpc.nfsd 2 || _fatal "rpc.nfsd failed to start"
rpc.mountd || _fatal "rpc.mountd failed to start"

touch /var/lib/nfs/etab
exportfs -a || _fatal "exportfs failed"

cd "$nfs_share"

set +x

pub_ips=()
_vm_ar_ip_addrs_nomask pub_ips
for i in "${pub_ips[@]}"; do
	echo "NFS export ready at: ${i}:${nfs_share}"
done
