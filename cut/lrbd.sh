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

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args "$RAPIDO_DIR/autorun/lrbd.sh" "$@"
_rt_require_networking
_rt_require_ceph
_rt_require_conf_dir LRBD_SRC TARGETCLI_SRC RTSLIB_SRC CONFIGSHELL_SRC
_rt_require_lib "libssl3.so libsmime3.so libstdc++.so.6 libsoftokn3.so \
		 libcrypto.so libexpat.so libudev.so \
		 libfreeblpriv3.so"	# NSS_InitContext() fails without

# _rt_require_rpms ?
py3_rpms="python3 python3-base python3-setuptools python3-pyudev python3-six \
	  python3-pyparsing python3-netifaces dbus-1-python3"
py3_files="$(rpm -ql $py3_rpms)" || _fail "missing python3 rpm(s) in: $py3_rpms"
# filter out unneeded pyc & doc files
py3_files=$(echo "$py3_files" | grep -v -e "\.pyc$" -e "/doc/")

[ -n "$CEPH_SRC" ] || _fail "$0 requires CEPH_SRC config"
rbd_bin="${CEPH_SRC}/build/bin/rbd"
[ -x "$rbd_bin" ] || _fail "rbd executable missing at $rbd_bin"
rados_cython="${CEPH_SRC}"/build/lib/cython_modules/lib.3/rados.cpython-34m.so
[ -x "$rados_cython" ] || _fail "rados cython library missing at $rados_cython"

# ldconfig needed by pyudev ctypes.util.find_library
"$DRACUT" --install "tail blockdev ps rmdir resize dd vim grep find df \
		   $py3_files env ldconfig \
		   dbus-daemon /etc/dbus-1/system.conf $rbd_bin $rados_cython \
		   $LIBS_INSTALL_LIST" \
	--include "$CEPH_CONF" "/etc/ceph/ceph.conf" \
	--include "$CEPH_KEYRING" "/etc/ceph/keyring" \
	--include "$RBD_NAMER_BIN" "/usr/bin/ceph-rbdnamer" \
	--include "$RBD_UDEV_RULES" "/usr/lib/udev/rules.d/50-rbd.rules" \
	--include "${LRBD_SRC}/lrbd" "/bin/lrbd" \
	--include "$RTSLIB_SRC" "/rtslib/" \
	--include "$TARGETCLI_SRC" "/targetcli/" \
	--include "$CONFIGSHELL_SRC" "/configshell/" \
	--add-drivers "iscsi_target_mod target_core_mod target_core_rbd" \
	--modules "base systemd systemd-initrd dracut-systemd" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"

# assign more memory
_rt_xattr_vm_resources_set "$DRACUT_OUT" "2" "1024M"
