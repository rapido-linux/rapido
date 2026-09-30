#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE S.A. 2025-2026, all rights reserved.
#
# Environment to run LKL unit tests.

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
sudo_fake="${tmpd}/sudo.fake"
trap "rm $pam_su $pam_other $etc_nsswitch $etc_passwd $etc_group $sudo_fake ; rmdir $tmpd" 0

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

printf -v req_inst_bins 'bin %s\n' "${req_inst[@]}"

PATH="target/release:${PATH}"
rapido-cut --manifest /dev/stdin <<EOF
# Static linking means LKL bins are heavy. Images are also thick provisioned
# with dd.
file /rapido-rsc/mem/6G

autorun autorun/lkl_tests.sh $*

$req_inst_bins
bin \${LKL_SRC}/tools/lkl/bin/lkl-hijack.sh
bin \${LKL_SRC}/tools/lkl/cptofs
bin \${LKL_SRC}/tools/lkl/lib/hijack/liblkl-hijack.so
bin \${LKL_SRC}/tools/lkl/lib/liblkl.so
bin \${LKL_SRC}/tools/lkl/lklfuse
bin \${LKL_SRC}/tools/lkl/tests
bin awk
bin blockdev
bin cat
bin chmod
bin cp
bin cut
bin date
bin dd
bin df
bin diff
bin dirname
bin false
bin file
bin find
bin free
bin fusermount3
bin grep
bin gzip
bin id
bin ip
bin ipcmk
bin ln
bin losetup
bin ls
bin lsusb
bin mkdir
bin mkfifo
bin mkfs
bin mkfs.btrfs
bin mkfs.ext4
bin mkfs.vfat
bin mkfs.xfs
bin mktemp
bin ping
bin ping6
bin ps
bin rm
bin rmdir
bin sed
bin sh
bin shuf
bin sleep
bin strace
bin strings
bin stty
bin su
bin tail
bin tc
bin tee
bin touch
bin true
bin unlink
bin uuidgen
bin wc
bin which
bin xfs_io
bin yes

# rapido-cut adds bash by default, but some lkl tests hardcode a /bin/bash path
bin /bin/bash
# some use "#!/usr/bin/env bash"
bin /usr/bin/env

slink /lib/liblkl.so \${LKL_SRC}/tools/lkl/lib/liblkl.so

# 'file' uses external magic metadata, install it if present.
try-bin /usr/share/file/magic.mgc
try-bin /usr/share/misc/magic.mgc
try-bin /usr/share/misc/magic

try-bin nano

file /etc/pam.d/su $pam_su
file /etc/pam.d/su-l $pam_su
file /etc/pam.d/other $pam_other
file /etc/nsswitch.conf $etc_nsswitch
file /bin/sudo $sudo_fake

# su needs this
file /etc/security/limits.conf
#file /etc/login.defs

kmod fuse
kmod tun
EOF
