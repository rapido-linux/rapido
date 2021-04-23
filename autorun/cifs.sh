#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2019, all rights reserved.
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

[ -n "$CIFS_UTILS_SRC" ] && ln -s "${CIFS_UTILS_SRC}/mount.cifs" /sbin/

creds_path="/tmp/cifs_creds"
[ -n "$CIFS_DOMAIN" ] && echo "domain=${CIFS_DOMAIN}" >> $creds_path
[ -n "$CIFS_USER" ] && echo "username=${CIFS_USER}" >> $creds_path
[ -n "$CIFS_PW" ] && echo "password=${CIFS_PW}" >> $creds_path
mount_args="-ocredentials=${creds_path}"
[ -n "$CIFS_MOUNT_OPTS" ] && mount_args="${mount_args},${CIFS_MOUNT_OPTS}"
set -x

mkdir -p /mnt/cifs
mount -t cifs //${CIFS_SERVER}/${CIFS_SHARE} /mnt/cifs \
	"$mount_args" || _fatal
cd /mnt/cifs || _fatal
set +x
