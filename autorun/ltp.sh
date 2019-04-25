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


if [ ! -f /vm_autorun.env ]; then
	echo "Error: autorun scripts must be run from within an initramfs VM"
	exit 1
fi

. /vm_autorun.env

LTP_DIR="/opt/ltp"
[ -d "$LTP_DIR" ] || _fatal "LTP missing"

_vm_ar_dyn_debug_enable

set -x

echo "running LTP Test $LTP_AUTORUN_CMD" 
#
if [ -n "$LTP_AUTORUN_CMD" ]; then
        cd ${LTP_DIR} || _fatal
        eval "$LTP_AUTORUN_CMD"
fi

