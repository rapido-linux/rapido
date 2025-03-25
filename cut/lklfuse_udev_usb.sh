#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2025, all rights reserved.
#
# Mount a USB attached block device as an unprivileged user via lklfuse.
# The mount is triggered via udev:61-lklfuse.rules->lklfuse-mount@.service .
#
# The USB device can be virtual, e.g.
# -drive if=none,id=stick,format=raw,file=/path/to/file.img \
# -device nec-usb-xhci,id=xhci                              \
# -device usb-storage,bus=xhci.0,drive=stick

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

_rt_require_dracut_args "$RAPIDO_DIR/autorun/lklfuse_udev_usb.sh" "$@"
_rt_require_conf_dir LKL_SRC
req_inst=()
_rt_require_pam_mods req_inst "pam_rootok.so" "pam_limits.so" "pam_deny.so"
_rt_mem_resources_set "2048M"

tmpd="$(mktemp -d --tmpdir lklfuse_tmp.XXXXX)"
pam_su="${tmpd}/su"
pam_other="${tmpd}/other"
etc_nsswitch="${tmpd}/nsswitch.conf"
trap "rm $pam_su $pam_other $etc_nsswitch ; rmdir $tmpd" 0

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

# lklfuse is installed and included... --install to pull in libs (libfuse3) and
# --include to place it in /usr/bin path used by the systemd service.
# loadkeys is run via systemd-vconsole-setup.service. Use true as an alias to
# avoid unnecessarily needing to install kbd maps.
# 'file' uses external magic metadata, install it if present.
"$DRACUT" --install "tail blockdev ps rmdir resize dd vim grep dirname df \
		   mktemp date file strings id find xfs_io \
		   strace mkfs mkfs.xfs shuf free su uuidgen losetup ipcmk \
		   which awk touch cut chmod true false unlink lsusb tee gzip \
		   ${LKL_SRC}/tools/lkl/lklfuse \
		   ${req_inst[*]}" \
	--install-optional /usr/share/file/magic.mgc \
	--install-optional /usr/share/misc/magic.mgc \
	--install-optional /usr/share/misc/magic \
	--include ${LKL_SRC}/tools/lkl/lklfuse /usr/bin/lklfuse \
	--include "${LKL_SRC}/tools/lkl/systemd/lklfuse-mount@.service" \
		  "/usr/lib/systemd/system/lklfuse-mount@.service" \
	--include "${LKL_SRC}/tools/lkl/systemd/61-lklfuse.rules" \
		  "/usr/lib/udev/rules.d/61-lklfuse.rules" \
	--include "$pam_su" /etc/pam.d/su \
	--include "$pam_su" /etc/pam.d/su-l \
	--include "$pam_other" /etc/pam.d/other \
	--include "$etc_nsswitch" /etc/nsswitch.conf \
	--include "${RAPIDO_DIR}/dracut.conf.d/.empty" \
		  /etc/security/limits.conf \
	--include "${RAPIDO_DIR}/dracut.conf.d/.empty" /etc/login.defs \
	--include /usr/bin/true /usr/bin/loadkeys \
	--add-drivers "fuse usb-storage xhci-hcd xhci-pci" \
	--modules "base dracut-systemd" \
	"${DRACUT_RAPIDO_ARGS[@]}" \
	"$DRACUT_OUT" || _fail "dracut failed"

# XXX: dracut strips setuid mode flags, so we append fusermount3 manually.
# An alternative would be to configure systemd with ProtectSystem=false and
# manually chmod.
fum3=$(type -P fusermount3) || _fail
echo "$fum3" | cpio --create -H newc >> "$DRACUT_OUT" || _fail
