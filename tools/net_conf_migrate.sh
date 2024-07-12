#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2022, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

echo "-> This helper script will not modify any existing files..."

unwind=""
trap "eval \$unwind" 0

_rapido_vm_conf_write() {
	local vm_num="$1"
	local parent_outdir="$2"
	typeset -n taps_ref="$3" || _fail
	local outdir="${parent_outdir}/vm${vm_num}"
	local outf
	local tap_num="$((vm_num - 1))"

	mkdir "$outdir" || _fail "mkdir failed"
	unwind="rmdir \"${outdir}\"; $unwind"

	eval local mac_addr='$MAC_ADDR'${vm_num}
	eval local tap='$TAP_DEV'${tap_num}
	eval local hostname='$HOSTNAME'${vm_num}
	eval local is_dhcp='$IP_ADDR'${vm_num}'_DHCP'
	eval local ip_addr='$IP_ADDR'${vm_num}

	[ -z $tap ] && _fail "TAP_DEV${tap_num} is unconfigured"
	if [[ -z $is_dhcp ]] && [[ -z $ip_addr ]]; then
		_fail "IP_ADDR${vm_num} and IP_ADDR${vm_num}_DHCP are unconfigured"
	fi

	taps_ref+=("$tap")
	outf="${outdir}/${tap}.network"
	cat > "$outf" <<EOF
# rapido.conf TAP_DEV${tap_num}=${tap} configuration migrated on $(date).
[Network]
EOF
	unwind="rm \"${outf}\"; $unwind"

	[[ -n $ip_addr ]] && cat >> "$outf" <<EOF
# rapido.conf:IP_ADDR${vm_num}=${ip_addr}
Address=$ip_addr"
EOF
	if [[ -n $is_dhcp ]]; then
		if [[ -n $ip_addr ]]; then
			# explicit IP takes precedence over DHCP
			cat >> "$outf" <<EOF
# rapido.conf:IP_ADDR${vm_num}_DHCP=${is_dhcp} ignored due to explicit IP_ADDR${vm_num} setting
#DHCP=yes
EOF
		else
			cat >> "$outf" <<EOF
# rapido.conf:IP_ADDR${vm_num}_DHCP=${is_dhcp}
DHCP=yes
EOF
		fi
	fi

	if [[ -n $hostname ]]; then
		cat >> "$outf" <<EOF
# rapido.conf:HOSTNAME${vm_num}=$hostname setting carried in ./hostname
EOF
		echo "$hostname" >> "${outdir}/hostname"
		unwind="rm \"${outdir}/hostname\"; $unwind"
	fi

	cat >> "$outf" <<EOF

# if unneeded, the following can be uncommented to speed up wait-online...
#LinkLocalAddressing=no
#LLMNR=no
EOF

	[[ -n $mac_addr ]] && cat >> "$outf" <<EOF

# An explicit MACAddress setting is no longer necessary, but this has been
# migrated in case it's relied on externally. Feel free to remove it:
[Link]
# rapido.conf:MAC_ADDR${vm_num}=${mac_addr}
MACAddress=${mac_addr}
EOF

	if [[ -n $BR_DHCP_SRV_RANGE ]] && [[ $vm_num == 1 ]]; then
		cat >> "$outf" <<EOF

# rapido.conf:BR_DHCP_SRV_RANGE=$BR_DHCP_SRV_RANGE
# As an alternative to running a DHCP server on the rapido host, vm1 could be
# configured to run it by setting DHCPServer=true in the [Network] section
# above, and then, e.g.
#[DHCPServer]
#PoolOffset=200
#PoolSize=20
EOF
	fi
}

tmpd=$(mktemp --tmpdir="$RAPIDO_DIR" --directory "net-conf.migrated.XXXXXXXXXX")
[[ -d $tmpd ]] || _fail "mktemp failed"
unwind="rmdir \"${tmpd}\"; $unwind"
tmpd=$(realpath "$tmpd")

read -p "Write rapido.conf based network config to \"${tmpd##*/}\"? (y/n): " \
     -n 1 -r
echo
[[ $REPLY =~ ^[Yy]$ ]] || _fail "Cancelled: \"y\" required to proceed."

tap_devs=()
for i in 1 2; do
	_rapido_vm_conf_write "$i" "$tmpd" tap_devs
done

cat << EOF
-> Complete: inspect then run "mv ${tmpd##*/} $VM_NET_CONF" to activate the config.
-> rapido.conf MAC_ADDR, TAP_DEV, HOSTNAME and IP_ADDR options can then be removed.
EOF

# success! clear unwind
unwind=""
