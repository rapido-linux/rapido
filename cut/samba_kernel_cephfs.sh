#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2019, all rights reserved.
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

_rt_require_dracut_args "$vm_ceph_conf" \
			"$RAPIDO_DIR/autorun/samba_kernel_cephfs.sh" "$@"
_rt_require_ceph
_rt_write_ceph_config $vm_ceph_conf
_rt_require_conf_dir SAMBA_SRC

"$DRACUT" --install "tail ps rmdir resize dd vim grep find df sha256sum \
		   strace stat which touch cut chmod true false \
		   getfattr setfattr getfacl setfacl killall sync \
		   id sort uniq date expr tac diff head dirname seq ip ping \
		   ${SAMBA_SRC}/bin/smbpasswd \
		   ${SAMBA_SRC}/bin/smbstatus \
		   ${SAMBA_SRC}/bin/smbd" \
	$DRACUT_RAPIDO_INCLUDES \
	--add-drivers "ceph libceph" \
	--modules "base" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT || _fail "dracut failed"

# assign more memory
_rt_xattr_vm_resources_set "$DRACUT_OUT" "2" "1024M"
