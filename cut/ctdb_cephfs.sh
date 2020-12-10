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

vm_ceph_conf="$(mktemp --tmpdir vm_ceph_conf.XXXXX)"
# remove tmp file once we're done
trap "rm $vm_ceph_conf" 0 1 2 3 15

_rt_require_ceph
_rt_write_ceph_config $vm_ceph_conf
_rt_require_samba_ctdb
_rt_require_dracut_args "$vm_ceph_conf" "$RAPIDO_DIR/autorun/ctdb_cephfs.sh" \
			"$@"
_rt_require_lib "libssl3.so libsmime3.so libstdc++.so.6 libsoftokn3.so \
		 libfreeblpriv3.so"	# NSS_InitContext() fails without

# XXX a few paths changed for Samba 4.9+:
# - ctdb_eventd -> ctdb-eventd
# - ctdb_event -> ctdb-event
# - config/events.d -> config/events
# - ctdb-config & ctdb-path -> new binaries
"$DRACUT" --install "tail blockdev ps rmdir resize dd vim grep find df sha256sum \
		   strace xargs timeout \
		   which perl awk bc touch cut chmod true false \
		   getfattr setfattr chacl attr killall sync \
		   id sort uniq date expr tac diff head dirname seq ip ping \
		   ${SAMBA_SRC}/bin/smbpasswd \
		   ${SAMBA_SRC}/bin/smbstatus \
		   ${SAMBA_SRC}/bin/modules/vfs/ceph.so \
		   ${SAMBA_SRC}/bin/smbd \
		   ${SAMBA_SRC}/bin/tdbtool \
		   ${SAMBA_SRC}/bin/ctdb \
		   ${SAMBA_SRC}/bin/ctdb-config \
		   ${SAMBA_SRC}/bin/ctdbd \
		   ${SAMBA_SRC}/bin/ctdb?event \
		   ${SAMBA_SRC}/bin/ctdb?eventd \
		   ${SAMBA_SRC}/bin/ctdb_killtcp \
		   ${SAMBA_SRC}/bin/ctdb_lock_helper \
		   ${SAMBA_SRC}/bin/ctdb_mutex_fcntl_helper \
		   ${SAMBA_SRC}/bin/ctdb-path \
		   ${SAMBA_SRC}/bin/ctdb_recovery_helper \
		   ${SAMBA_SRC}/bin/ctdb_takeover_helper \
		   ${SAMBA_SRC}/bin/ctdb_mutex_ceph_rados_helper \
		   $LIBS_INSTALL_LIST" \
	--include "$CTDB_EVENTS_DIR" "$CTDB_EVENTS_DIR" \
	--include "${SAMBA_SRC}/ctdb/config/functions" \
		  "/usr/local/samba/etc/ctdb/functions" \
	--include "$CEPH_COMMON_LIB" "/usr/lib64/libceph-common.so.0" \
	--include "$CEPHFS_LIB" "/usr/lib64/libcephfs.so.2" \
	--include "$CEPH_RADOS_LIB" "/usr/lib64/librados.so.2" \
	--include "$CEPH_CONF" "/etc/ceph/ceph.conf" \
	--include "$CEPH_KEYRING" "/etc/ceph/keyring" \
	$DRACUT_RAPIDO_INCLUDES \
	--modules "bash base" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT || _fail "dracut failed"

# assign more memory
_rt_xattr_vm_resources_set "$DRACUT_OUT" "2" "1024M"
