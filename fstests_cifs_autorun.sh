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

if [ ! -f /early_cpio ]; then
	echo "Error: autorun scripts must be run from within an initramfs VM"
	exit 1
fi

. /vm_autorun.env

set -x

# path to xfstests within the initramfs
XFSTESTS_DIR="/fstests/xfstests"

hostname_fqn="`cat /proc/sys/kernel/hostname`" || _fatal "hostname unavailable"
hostname_short="${hostname_fqn%%.*}"

# need hosts file for hostname -s
cat > /etc/hosts <<EOF
127.0.0.1	$hostname_fqn	$hostname_short
EOF

# enable debugfs
cat /proc/mounts | grep debugfs &> /dev/null
if [ $? -ne 0 ]; then
	mount -t debugfs debugfs /sys/kernel/debug/
fi

cat /proc/mounts | grep configfs &> /dev/null
if [ $? -ne 0 ]; then
	mount -t configfs configfs /sys/kernel/config/
fi

for i in $DYN_DEBUG_MODULES; do
	echo "module $i +pf" > /sys/kernel/debug/dynamic_debug/control || _fatal
done
for i in $DYN_DEBUG_FILES; do
	echo "file $i +pf" > /sys/kernel/debug/dynamic_debug/control || _fatal
done

creds_path="/tmp/cifs_creds"
[ -n "$CIFS_DOMAIN" ] && echo "domain=${CIFS_DOMAIN}" >> $creds_path
[ -n "$CIFS_USER" ] && echo "username=${CIFS_USER}" >> $creds_path
[ -n "$CIFS_PW" ] && echo "password=${CIFS_PW}" >> $creds_path
mount_args="-ocredentials=${creds_path}"
[ -n "$CIFS_MOUNT_OPTS" ] && mount_args="${mount_args},${CIFS_MOUNT_OPTS}"

mkdir -p /mnt/test
mount -t cifs //${CIFS_SERVER}/${CIFS_SHARE} /mnt/test \
	"$mount_args" || _fatal

cat > ${XFSTESTS_DIR}/configs/`hostname -s`.config << EOF
MODULAR=0
TEST_DIR=/mnt/test
TEST_DEV=//${CIFS_SERVER}/${CIFS_SHARE}
TEST_FS_MOUNT_OPTS="$mount_args"
EOF

set +x

if [ -n "$FSTESTS_AUTORUN_CMD" ]; then
	cd ${XFSTESTS_DIR} || _fatal
	eval "$FSTESTS_AUTORUN_CMD"
fi
