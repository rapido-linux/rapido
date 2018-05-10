#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2018, all rights reserved.
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

# autorun scripts are run immediately once the Rapido scratch VM has booted...

# protect against running (harmful) scripts outside of Rapido VMs
if [ ! -f /vm_autorun.env ]; then
	echo "Error: autorun scripts must be run from within an initramfs VM"
	exit 1
fi

. /vm_autorun.env

# echo shell commands as they are executed
set -x

# mount kernel debugfs
cat /proc/mounts | grep debugfs &> /dev/null
if [ $? -ne 0 ]; then
	mount -t debugfs debugfs /sys/kernel/debug/
fi
# mount kernel configfs
cat /proc/mounts | grep configfs &> /dev/null
if [ $? -ne 0 ]; then
	mount -t configfs configfs /sys/kernel/config/
fi

# enable dynamic debug for any modules or files specified in rapido.conf
# all kernel modules *should* be loaded before reaching this point
for i in $DYN_DEBUG_MODULES; do
	echo "module $i +pf" > /sys/kernel/debug/dynamic_debug/control || _fatal
done
for i in $DYN_DEBUG_FILES; do
	echo "file $i +pf" > /sys/kernel/debug/dynamic_debug/control || _fatal
done

set +x

# actual *test* script starts below...

# load the zram kernel module, which was installed via the --add-drivers "zram"
# parameter in the cut script. Provision a single zram device
modprobe zram num_devices="1" || _fatal "failed to load zram module"
# failures resulting in a call to _fatal() will shutdown the VM

# set the size of the zram device.
echo "100M" > /sys/block/zram0/disksize || _fatal "failed to set zram disksize"

echo "Rapido scratch VM running. Have a lot of fun..."
# end of *test* script.

# returning here will drop into the Dracut shell prompt.
# "shutdown" can be called to shutdown the VM (see vm_autorun.env alias).
