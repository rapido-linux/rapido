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

RAPIDO_DIR="$(realpath -e ${0%/*})"
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_ceph
_rt_require_samba_ctdb
_rt_require_dracut_args
_rt_require_lib "libssl3.so libsmime3.so libstdc++.so.6 libsoftokn3.so \
		 libfreeblpriv3.so"	# NSS_InitContext() fails without

# ctdb_cephfs_autorun.sh deploys a three-node CTDB cluster
if [ -z "$MAC_ADDR1" ] || [ -z "$MAC_ADDR2" ] || [ -z "$MAC_ADDR3" ]; then
	_fail "$0 requires three VM network adapters in rapido.conf"
fi

# XXX a few paths changed for Samba 4.9+:
# - ctdb_eventd -> ctdb-eventd
# - ctdb_event -> ctdb-event
# - config/events.d -> config/events
# - ctdb-config & ctdb-path -> new binaries
"$DRACUT" --install "tail blockdev ps rmdir resize dd vim grep find df sha256sum \
		   strace xargs timeout \
		   which perl awk bc touch cut chmod true false \
		   fio getfattr setfattr chacl attr killall sync \
		   id sort uniq date expr tac diff head dirname seq \
		   ${SAMBA_SRC}/bin/default/source3/utils/smbpasswd \
		   ${SAMBA_SRC}/bin/default/source3/smbstatus \
		   ${SAMBA_SRC}/bin/modules/vfs/ceph.so \
		   ${SAMBA_SRC}/bin/default/source3/smbd/smbd \
		   ${SAMBA_SRC}/bin/default/lib/tdb/tdbtool \
		   ${SAMBA_SRC}/bin/default/ctdb/ctdb \
		   ${SAMBA_SRC}/bin/default/ctdb/ctdb-config \
		   ${SAMBA_SRC}/bin/default/ctdb/ctdbd \
		   ${SAMBA_SRC}/bin/default/ctdb/ctdb?event \
		   ${SAMBA_SRC}/bin/default/ctdb/ctdb?eventd \
		   ${SAMBA_SRC}/bin/default/ctdb/ctdb_killtcp \
		   ${SAMBA_SRC}/bin/default/ctdb/ctdb_lock_helper \
		   ${SAMBA_SRC}/bin/default/ctdb/ctdb_mutex_fcntl_helper \
		   ${SAMBA_SRC}/bin/default/ctdb/ctdb_packet_parse \
		   ${SAMBA_SRC}/bin/default/ctdb/ctdb-path \
		   ${SAMBA_SRC}/bin/default/ctdb/ctdb_recovery_helper \
		   ${SAMBA_SRC}/bin/default/ctdb/ctdb_takeover_helper \
		   ${SAMBA_SRC}/bin/default/ctdb/ctdb_mutex_ceph_rados_helper \
		   $LIBS_INSTALL_LIST" \
	--include "$CTDB_EVENTS_DIR" "$CTDB_EVENTS_DIR" \
	--include "${SAMBA_SRC}/ctdb/config/functions" \
		  "/usr/local/samba/etc/ctdb/functions" \
	--include "$CEPH_COMMON_LIB" "/usr/lib64/libceph-common.so.0" \
	--include "$CEPHFS_LIB" "/usr/lib64/libcephfs.so.2" \
	--include "$CEPH_RADOS_LIB" "/usr/lib64/librados.so.2" \
	--include "$CEPH_CONF" "/etc/ceph/ceph.conf" \
	--include "$CEPH_KEYRING" "/etc/ceph/keyring" \
	--include "$RAPIDO_DIR/ctdb_cephfs_autorun.sh" "/.profile" \
	--include "$RAPIDO_DIR/rapido.conf" "/rapido.conf" \
	--include "$RAPIDO_DIR/vm_autorun.env" "/vm_autorun.env" \
	--modules "bash base network ifcfg" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT || _fail "dracut failed"

# assign more memory
_rt_xattr_vm_resources_set "$DRACUT_OUT" "2" "1024M"
