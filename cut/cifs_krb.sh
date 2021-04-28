#!/bin/bash
#
# Copyright (C) SUSE LLC 2021, all rights reserved.
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

_rt_require_dracut_args "$RAPIDO_DIR/autorun/cifs_krb.sh" "$@"
_rt_require_lib "libnss_dns.so"
_rt_require_cifs_utils
_rt_require_conf_setting CIFS_DOMAIN CIFS_USER CIFS_PW CIFS_SHARE

"$DRACUT" --install "tail ps rmdir resize dd vim grep find df \
		   ip ping truncate du which touch chmod \
		   killall sync dirname seq basename stat \
		   request-key kinit klist \
		   $LIBS_INSTALL_LIST \
		   $CIFS_UTILS_BINS" \
	$DRACUT_RAPIDO_INCLUDES \
	--add-drivers "cifs ccm gcm ctr" \
	--modules "base" \
	$DRACUT_EXTRA_ARGS \
	$DRACUT_OUT || _fail "dracut failed"
