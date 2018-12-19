#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2016, all rights reserved.
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

if [ ! -f /vm_autorun.env ]; then
	echo "Error: autorun scripts must be run from within an initramfs VM"
	exit 1
fi

. /vm_autorun.env

set -x

# path to xfstests within the initramfs
XFSTESTS_DIR="/fstests"

hostname_fqn="`cat /proc/sys/kernel/hostname`" || _fatal "hostname unavailable"
hostname_short="${hostname_fqn%%.*}"

# need hosts file for hostname -s
cat > /etc/hosts <<EOF
127.0.0.1	$hostname_fqn	$hostname_short
EOF

_vm_ar_dyn_debug_enable

set +x
creds_path="/tmp/cifs_creds"
[ -n "$CIFS_DOMAIN" ] && echo "domain=${CIFS_DOMAIN}" >> $creds_path
[ -n "$CIFS_USER" ] && echo "username=${CIFS_USER}" >> $creds_path
[ -n "$CIFS_PW" ] && echo "password=${CIFS_PW}" >> $creds_path
mount_args="-ocredentials=${creds_path}"
[ -n "$CIFS_MOUNT_OPTS" ] && mount_args="${mount_args},${CIFS_MOUNT_OPTS}"
set -x

mkdir -p /mnt/test
mount -t cifs //${CIFS_SERVER}/${CIFS_SHARE} /mnt/test \
	"$mount_args" || _fatal

cat > ${XFSTESTS_DIR}/configs/`hostname -s`.config << EOF
MODULAR=0
TEST_DIR=/mnt/test
TEST_DEV=//${CIFS_SERVER}/${CIFS_SHARE}
TEST_FS_MOUNT_OPTS="$mount_args"
EOF

if [ -n "$FSTESTS_EXCLUDE" ]; then
	exclude="${FSTESTS_SRC}/configs/$(hostname -s).exclude"
	for excl in $FSTESTS_EXCLUDE; do
		echo $excl >> $exclude;
	done
fi

set +x

if [ -n "$FSTESTS_AUTORUN_CMD" ]; then
	cd ${XFSTESTS_DIR} || _fatal
	eval "$FSTESTS_AUTORUN_CMD"
fi
