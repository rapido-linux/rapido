#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE S.A. 2019-2026, all rights reserved.

_vm_ar_env_check || exit 1

_vm_ar_dyn_debug_enable

creds_path="/tmp/cifs_creds"
[[ -n "$CIFS_DOMAIN" ]] && echo "domain=${CIFS_DOMAIN}" >> $creds_path
[[ -n "$CIFS_USER" ]] && echo "username=${CIFS_USER}" >> $creds_path
[[ -n "$CIFS_PW" ]] && echo "password=${CIFS_PW}" >> $creds_path
mount_args="-ocredentials=${creds_path}"
[[ -n "$CIFS_MOUNT_OPTS" ]] && mount_args="${mount_args},${CIFS_MOUNT_OPTS}"
set -x

[[ -n "$CIFS_SERVER" ]] || _fatal "CIFS_SERVER configuration missing"
[[ -n "$CIFS_SHARE" ]] || _fatal "CIFS_SHARE configuration missing"

mkdir -p /mnt/cifs
mount -t cifs //${CIFS_SERVER}/${CIFS_SHARE} /mnt/cifs \
	"$mount_args" || _fatal
cd /mnt/cifs || _fatal
set +x
