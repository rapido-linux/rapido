#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2022, all rights reserved.

_ceph_rbd_map() {
	[ -z "$CEPH_USER" ] && _fatal "CEPH_USER not configured"
	[ -z "$CEPH_RBD_POOL" ] && _fatal "CEPH_RBD_POOL not configured"
	[ -z "$CEPH_RBD_IMAGE" ] && _fatal "CEPH_RBD_IMAGE not configured"
	[ -z "$CEPH_MON_ADDRESS_V1" ] && _fatal "CEPH_MON_ADDRESS_V1 not configured"
	[ -z "$CEPH_USER_KEY" ] && _fatal "CEPH_USER_KEY not configured"

	# start udevd, otherwise rbd hangs in wait_for_udev_add()
	/usr/lib/systemd/systemd-udevd --daemon

	local add_path
	for add_path in /sys/bus/rbd/add_single_major /sys/bus/rbd/add; do
		[ -f "$add_path" ] || continue

		echo -n "${CEPH_MON_ADDRESS_V1} \
			 name=${CEPH_USER},secret=${CEPH_USER_KEY} \
			 $CEPH_RBD_POOL $CEPH_RBD_IMAGE -" \
			> "$add_path" || _fatal "RBD map failed"
		udevadm settle || _fatal
		return
	done

	echo "rbd sysfs interface not found"
	_fatal
}
