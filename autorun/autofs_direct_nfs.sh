#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2025, all rights reserved.

_vm_ar_env_check || exit 1

modprobe autofs4
_vm_ar_dyn_debug_enable
_vm_ar_hosts_create

[[ -n $NFS_SERVER && -n $NFS_SHARE ]] \
	|| _fatal "NFS_SERVER and NFS_SHARE must be set in rapido.conf"
[[ -n $NFS_MOUNT_OPTS ]] && mount_args="-o${NFS_MOUNT_OPTS}"

# use a non-configurable UID/GID for now
nfs_xid="579121"
nfs_user="nfsuser"
_nfs_etc_files_setup "$nfs_xid" "$nfs_user"

mkdir -p /etc/sysconfig /nfs/share
touch /etc/sysconfig/autofs	# avoid noise

echo "automount: files" > /etc/nsswitch.conf
echo "[ autofs ]" > /etc/autofs.conf

cat > /etc/auto.master <<EOF
/-	/etc/auto.direct
EOF
cat > /etc/auto.direct <<EOF
/nfs/share  $mount_args ${NFS_SERVER}:/${NFS_SHARE}
EOF

if [ -n "$AUTOFS_SRC" ]; then
	for l in /usr/lib/autofs /usr/lib64/autofs; do
		mkdir -p "$l"
		pushd "$l"
		ln -s ${AUTOFS_SRC}/lib/*.so .
		ln -s ${AUTOFS_SRC}/modules/*.so .
		# see autofs/modules/Makefile...
		ln -s "lookup_file.so" "lookup_files.so"
		popd
	done
	export PATH="${AUTOFS_SRC}/daemon:$PATH"
fi

automount --dumpmaps
automount

set +x
