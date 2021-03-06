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

_vm_ar_env_check || exit 1

# block ssh client shells from triggering the dracut autorun script
if [ -n "$SSH_CLIENT" ]; then
	export PS1="dropbear:\${PWD}# "
	return
fi

set -x

_vm_ar_dyn_debug_enable

mkdir --mode=0700 -p /etc/dropbear/ || _fatal
if [ -n "$SSH_AUTHORIZED_KEY" ]; then
	auth_keys_dir="/root/.ssh"
	mkdir --mode=0700 -p $auth_keys_dir || _fatal
	echo "$SSH_AUTHORIZED_KEY" >> ${auth_keys_dir}/authorized_keys
	chmod 0600 ${auth_keys_dir}/authorized_keys || _fatal
fi

dropbear -Rs

set +x
