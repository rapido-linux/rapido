#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2022, all rights reserved.

_ublksrv_env_init() {
	export PATH="${PATH}:${UBLKSRV_SRC}/.libs"
	export LD_LIBRARY_PATH="${UBLKSRV_SRC}/lib/.libs"

	if [ -n "$LIBURING_SRC" ]; then
		LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:${LIBURING_SRC}/src"
		# ublk expects a major version symlink...
		for i in $(ls ${LIBURING_SRC}/src/liburing.so.[0-9].*); do
			ln -s "$i" "${i%.*}"
		done
	fi

	# ublk logs to /dev/log
	#nc -lUk /dev/log &
}
