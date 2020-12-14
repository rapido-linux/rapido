#!/bin/bash
#
# Copyright (C) SUSE LLC 2019, all rights reserved.
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

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args "$RAPIDO_DIR/autorun/nvme_tcp_initiator.sh" "$@"

"$DRACUT" --install "tail blockdev ps rmdir resize dd vim grep find df sha256sum \
		   strace mkfs.xfs ip ping" \
	$DRACUT_RAPIDO_INCLUDES \
	--include "$vm_ceph_conf" "/vm_ceph.env" \
	--add-drivers "nvme-core nvme-fabrics nvme-tcp" \
	--modules "$DRACUT_RAPIDO_MODULES" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT
