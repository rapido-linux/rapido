#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2025, all rights reserved.
#
# Environment to run LKL unit tests.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args "$RAPIDO_DIR/autorun/lkl_tests.sh" "$@"
_rt_require_conf_dir LKL_SRC
req_inst=()
_rt_require_pam_mods req_inst "pam_rootok.so" "pam_limits.so" "pam_deny.so"
_rt_mem_resources_set "2048M"

tmpd="$(mktemp -d --tmpdir lklfuse_tmp.XXXXX)"
pam_su="${tmpd}/su"
pam_other="${tmpd}/other"
etc_nsswitch="${tmpd}/nsswitch.conf"
sudo_fake="${tmpd}/sudo.fake"
trap "rm $pam_su $pam_other $etc_nsswitch $sudo_fake ; rmdir $tmpd" 0

cat > $pam_su <<EOF
auth	sufficient	pam_rootok.so
account	sufficient	pam_rootok.so
session	required	pam_limits.so
EOF

for i in auth account password session; do
	echo "$i required pam_deny.so" >> $pam_other
done

cat > $etc_nsswitch <<EOF
passwd: files
group: files
EOF

cat > "$sudo_fake" <<EOF
#!/bin/bash -x
if (( \$UID != 0 )); then
	echo "error: fake sudo only works as root!"
	exit 1
fi

#echo "fake sudo running: \$@"
\$@
EOF
chmod 755 "$sudo_fake"

# 'file' uses external magic metadata, install it if present.
"$DRACUT" --install "tail blockdev ps rmdir resize dd vim grep dirname df id \
		   mktemp date file strings find xfs_io mkfifo ping ping6 ip \
		   strace mkfs mkfs.ext4 shuf free su uuidgen losetup ipcmk \
		   which awk touch cut chmod true false unlink lsusb tee gzip \
		   yes wc tc \
		   ${LKL_SRC}/tools/lkl/lklfuse \
		   ${LKL_SRC}/tools/lkl/tests/* \
		   ${LKL_SRC}/tools/lkl/bin/lkl-hijack.sh \
		   ${LKL_SRC}/tools/lkl/lib/hijack/liblkl-hijack.so \
		   ${req_inst[*]}" \
	--install-optional /usr/share/file/magic.mgc \
	--install-optional /usr/share/misc/magic.mgc \
	--install-optional /usr/share/misc/magic \
	--install-optional netperf \
	--include ${LKL_SRC}/tools/lkl/lib/liblkl.so /lib/liblkl.so \
	--include "$pam_su" /etc/pam.d/su \
	--include "$pam_su" /etc/pam.d/su-l \
	--include "$pam_other" /etc/pam.d/other \
	--include "$etc_nsswitch" /etc/nsswitch.conf \
	--include "$sudo_fake" /bin/sudo \
	--include "${RAPIDO_DIR}/dracut.conf.d/.empty" \
		  /etc/security/limits.conf \
	--include "${RAPIDO_DIR}/dracut.conf.d/.empty" /etc/login.defs \
	--add-drivers "fuse" \
	--modules "base" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"

# XXX: dracut strips setuid mode flags, so we append fusermount3 manually.
# An alternative would be to configure systemd with ProtectSystem=false and
# manually chmod.
fum3=$(type -P fusermount3) || _fail
echo "$fum3" | cpio --create -H newc >> "$DRACUT_OUT" || _fail
