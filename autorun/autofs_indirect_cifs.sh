#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2021, all rights reserved.

_vm_ar_env_check || exit 1

modprobe autofs4
_vm_ar_dyn_debug_enable

creds_path="/tmp/cifs_creds"
[ -n "$CIFS_DOMAIN" ] && echo "domain=${CIFS_DOMAIN}" >> $creds_path
[ -n "$CIFS_USER" ] && echo "username=${CIFS_USER}" >> $creds_path
[ -n "$CIFS_PW" ] && echo "password=${CIFS_PW}" >> $creds_path
mount_args="-fstype=cifs,credentials=${creds_path}"
[ -n "$CIFS_MOUNT_OPTS" ] && mount_args="${mount_args},${CIFS_MOUNT_OPTS}"
set -x

mkdir -p /etc/sysconfig /smb
touch /etc/sysconfig/autofs	# avoid noise

echo "automount: files" > /etc/nsswitch.conf
echo "[ autofs ]" > /etc/autofs.conf

cat > /etc/auto.master <<EOF
/smb	/etc/auto.indirect.smb
EOF
cat > /etc/auto.indirect.smb <<EOF
share ${mount_args} ://${CIFS_SERVER}/${CIFS_SHARE}
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
