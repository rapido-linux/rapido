#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LINUX GmbH 2018, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args "$RAPIDO_DIR/autorun/lrbd.sh" "$@"
_rt_require_networking
_rt_require_ceph
_rt_require_conf_dir LRBD_SRC TARGETCLI_SRC RTSLIB_SRC CONFIGSHELL_SRC
req_inst=()
_rt_require_lib req_inst "libssl3.so libsmime3.so libstdc++.so.6 libsoftokn3.so \
		 libcrypto.so libexpat.so libudev.so \
		 libfreeblpriv3.so"	# NSS_InitContext() fails without
# assign more memory
_rt_mem_resources_set "1024M"

systemd_conf="$(mktemp --tmpdir systemd_conf.XXXXX)"
trap "rm $systemd_conf" 0

# ensure /usr is writeable
cat >"$systemd_conf" <<EOF
[Manager]
ProtectSystem=false
EOF

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
		   ${req_inst[*]}" \
	--include "$CEPH_CONF" "/etc/ceph/ceph.conf" \
	--include "$CEPH_KEYRING" "/etc/ceph/keyring" \
	--include "$RBD_NAMER_BIN" "/usr/bin/ceph-rbdnamer" \
	--include "$RBD_UDEV_RULES" "/usr/lib/udev/rules.d/50-rbd.rules" \
	--include "${LRBD_SRC}/lrbd" "/bin/lrbd" \
	--include "$RTSLIB_SRC" "/rtslib/" \
	--include "$TARGETCLI_SRC" "/targetcli/" \
	--include "$CONFIGSHELL_SRC" "/configshell/" \
	--include "$systemd_conf" "/etc/systemd/system.conf.d/60-rapido.conf" \
	--add-drivers "iscsi_target_mod target_core_mod target_core_rbd" \
	--modules "base systemd systemd-initrd dracut-systemd" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"
