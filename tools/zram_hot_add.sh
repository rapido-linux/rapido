#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2017, all rights reserved.
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

# hot provision a new zram compressed ramdisk

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

function _zram_hot_add() {
	local zram_size="$1"
	local zram_owner="$2"
	local zram_num=$(cat /sys/class/zram-control/hot_add) \
		|| _fail "zram hot add failed"
	local zram_dev="/dev/zram${zram_num}"

	echo "$zram_size" > \
		/sys/devices/virtual/block/zram${zram_num}/disksize \
		|| _fail "failed to set size for $zram_dev"
	chown "$zram_owner" "$zram_dev" || _fail "failed to set $zram_dev owner"
	echo "$zram_dev"
}

function _usage()
{
	echo "Usage: $(basename $0) <size>[K|M|G] <owner>[:group]"
	exit 1
}

modprobe zram num_devices=0
[ -e /sys/class/zram-control/hot_add ] \
	|| _fail "zram hot_add sysfs path missing (old kernel?)"

[ "$#" != "2" ] && _usage
ZRAM_SIZE="$1"
ZRAM_OWNER="$2"

set -x

_zram_hot_add "$ZRAM_SIZE" "$ZRAM_OWNER"
