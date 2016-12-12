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

#### ddiss - start udevd, so that the rbdnamer hook is invoked
ps -eo args | grep -v grep | grep /usr/lib/systemd/systemd-udevd \
	|| /usr/lib/systemd/systemd-udevd --daemon

# ensure that conf FS is exposed before RBD mapping
touch /usr/lib/rbd-usb-run-conf.flag

# in background so that the wait-for-eject loop doesn't block the cmdline
/bin/conf-fs.sh &

set +x
