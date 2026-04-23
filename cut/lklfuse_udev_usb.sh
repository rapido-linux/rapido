#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE S.A. 2025-2026, all rights reserved.
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

req_inst=()
_rt_require_pam_mods req_inst "pam_rootok.so" "pam_limits.so" "pam_deny.so"

tmpd="$(mktemp -d --tmpdir lklfuse_tmp.XXXXX)"
pam_su="${tmpd}/su"
pam_other="${tmpd}/other"
etc_nsswitch="${tmpd}/nsswitch.conf"
etc_passwd="${tmpd}/passwd"
etc_group="${tmpd}/group"
system_init_tgt="${tmpd}/system_init_tgt"
trap "rm $pam_su $pam_other $etc_nsswitch $etc_passwd $etc_group $system_init_tgt; rmdir $tmpd" 0

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

cat > $etc_passwd <<EOF
root:x:0:0:root:/:/bin/bash
daemon:x:2:2:Daemon:/:/dev/null
lklfuse:x:2000:2000:lklfuse user:/:/bin/bash
person:x:2001:2001:user:/:/bin/bash
lklfusemember:x:2002:2002:lklfusemember user:/:/bin/bash
EOF

cat > $etc_group <<EOF
root:x:0:
disk:x:489:
lklfuse:x:2000:lklfusemember
person:x:2001:lklfusemember
lklfusemember:x:2002:
EOF

printf -v req_inst_bins 'bin %s\n' "${req_inst[@]}"

cat > $system_init_tgt <<EOF
[Unit]
Description=System Initialization
EOF

PATH="target/release:${PATH}"
rapido-cut --manifest /dev/stdin <<EOF
file /rapido-rsc/mem/2048M

include systemd.fest

autorun autorun/lklfuse_udev_usb.sh $*

bin \${LKL_SRC}/tools/lkl/lklfuse
# path used by systemd service
slink /usr/bin/lklfuse \${LKL_SRC}/tools/lkl/lklfuse

$req_inst_bins
bin /usr/lib/systemd/systemd-udevd
bin awk
bin blockdev
bin cat
bin chmod
bin cut
bin date
bin dd
bin df
bin dirname
bin false
bin file
bin find
bin free
bin fusermount3
bin grep
bin gzip
bin id
bin ipcmk
bin losetup
bin ls
bin lsusb
bin mkfs
bin mkfs.xfs
bin mktemp
bin ps
bin resize
bin rm
bin rmdir
bin shuf
bin strace
bin strings
bin su
bin tail
bin tee
bin touch
bin true
bin udevadm
bin unlink
bin uuidgen
bin vim
bin which
bin xfs_io
# lklfuse invokes /bin/bash, so we at least need a symlink there
bin /bin/bash

# 'file' uses external magic metadata, install it if present.
try-bin /usr/share/file/magic.mgc
try-bin /usr/share/misc/magic.mgc
try-bin /usr/share/misc/magic

file /usr/lib/systemd/system/modprobe@.service /usr/lib/systemd/system/modprobe@.service
file /usr/lib/systemd/system/systemd-udevd.service /usr/lib/systemd/system/systemd-udevd.service

# needed for modprobe@.service and other host services
file /usr/lib/systemd/system/sysinit.target $system_init_tgt

file /usr/lib/systemd/system/lklfuse-mount@.service \${LKL_SRC}/tools/lkl/systemd/lklfuse-mount@.service

# TODO: we should only need a subset of udev rules
tree /usr/lib/udev/rules.d /usr/lib/udev/rules.d
# FIXME: if the above tree rules.d recursion finds a host 61-lklfuse.rules then
# this won't have any effect. Also, we can't put the file before the tree or the
# tree traversal will skip recursion of the seen parent. TODO: filter this path
# above and then "unfilter" so that the path can be used?
file /usr/lib/udev/rules.d/61-lklfuse.rules \${LKL_SRC}/tools/lkl/systemd/61-lklfuse.rules

file /etc/pam.d/su $pam_su
file /etc/pam.d/su-l $pam_su
file /etc/pam.d/other $pam_other
file /etc/nsswitch.conf $etc_nsswitch
file /etc/passwd $etc_passwd
file /etc/group $etc_group

# su needs this
file /etc/security/limits.conf

kmod fuse
kmod sd_mod
kmod uas
kmod usb-storage
kmod xhci-hcd
kmod xhci-pci
EOF
