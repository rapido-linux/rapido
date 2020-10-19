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

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args "$RAPIDO_DIR/autorun/nvme_rdma.sh"
_rt_require_lib "libkeyutils.so.1"

"$DRACUT" --install "$DRACUT_RAPIDO_INSTALL \
		tail blockdev ps rmdir resize dd vim grep find df sha256sum \
		strace mkfs.xfs killall nvme ip ping \
		$LIBS_INSTALL_LIST" \
	$DRACUT_RAPIDO_INCLUDES \
	--add-drivers "nvme-core nvme-fabrics nvme-rdma nvmet nvmet-rdma \
		       rdma_rxe zram lzo lzo-rle ib_core ib_uverbs rdma_ucm \
		       crc32_generic" \
	--modules "bash base" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT
