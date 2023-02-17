#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2023, all rights reserved.

_vm_ar_env_check || exit 1
modprobe -a ocfs2 virtio_blk || _fatal
_vm_ar_dyn_debug_enable

mkdir -p /etc/ocfs2 /mnt/ocfs2

# add the first IP for each network-configured rapido VM
for ((node = 1; node < 10; node++)); do
	node_ips=()
	_vm_ar_cfg_ips_nomask "$node" node_ips
	if (( ${#node_ips[*]} == 0 )); then
		break
	elif (( ${#node_ips[*]} > 1 )); then
		echo "only using first IP (${node_ips[0]}) for vm $node"
	fi

	cat >> /etc/ocfs2/cluster.conf <<EOF
node:
	ip_port = 7777
	ip_address = ${node_ips[0]}
	number = $node
	name = rapido${node}
	cluster = rapidocluster
EOF
done

cat >> /etc/ocfs2/cluster.conf <<EOF
cluster:
	node_count = $((node - 1))
	name = rapidocluster
EOF

# expect a device with serial=OCFS2
declare -A _CFG=(["OCFS2"]="")
for i in $(ls /sys/block); do
	ser="$(cat /sys/block/${i}/serial 2>/dev/null)" || continue
	[[ -v "_CFG[$ser]" ]] && _CFG[$ser]="/dev/${i}"
done

[ -b "${_CFG[OCFS2]}" ] || _fatal "block device with serial=OCFS2 required"

# configfs needed for o2cb
_vm_ar_configfs_mount

set -x
o2cb register-cluster rapidocluster || _fatal

# first rapido VM does the mkfs
if (( $kcli_rapido_vm_num == 1 )); then
	# mkfs manually prompts before overwrite and returns 1 on 'n', so
	# ignore failure here. IO errors should anyhow be caught by mount.
	mkfs.ocfs2 --force "${_CFG[OCFS2]}"
fi

mount "${_CFG[OCFS2]}" /mnt/ocfs2 || _fatal
set +x
