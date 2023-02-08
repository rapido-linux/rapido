#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2022, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

# we could provide host bridge/tap deployment via systemd-networkd, but it
# shouldn't be required on the host system, so use iproute2 only.
br_name="$BR_DEV"
tap_owner="$TAP_USER"	# TODO default to env SUDO_USER?
br_addr="$BR_ADDR"

_usage() {
	local err=$1
	local ret=0

	if [[ -n $err ]]; then
		echo -e "Error: $err\n"
		ret=1
	fi
	cat <<EOF
Usage: rapido setup-network [OPTIONS]

OPTIONS:
  -o <tap-owner>:   tap device owner (default: rapido.conf TAP_USER)
  -b <bridge-name>: name of bridge device (default: rapido.conf BR_DEV)
  -a <bridge-addr>: IP address assigned to bridge (default: rapido.conf BR_ADDR)
  -h:               show this usage message
EOF
	exit "$ret"
}

_tap_manifest_gen() {
	manifest="$1"
	br_dev="$2"
	local i vm_tap

	[[ -d $VM_NET_CONF ]] \
		|| fail "$VM_NET_CONF directory missing, see net-conf.example"

	cat > "$manifest" << EOF
# The following tap devices will be created alongside "${br_dev}":
EOF
	shopt -s nullglob
	for i in ${VM_NET_CONF}/vm[0-9]*/*.network; do
		[[ $i =~ /vm[0-9]*/(.*)\.network$ ]] || continue
		vm_tap="${BASH_REMATCH[1]}"
		if [[ -d /sys/class/net/${vm_tap} ]]; then
			echo "# \"$vm_tap\" already exists" >> "$manifest"
		else
			echo "$vm_tap" >> "$manifest"
		fi
	done
	cat >> "$manifest" << EOF

# Entries can be added or removed from the list above.
# Empty and '#' prefixed lines will be ignored. Exit to continue...
EOF
}

while getopts "o:b:a:h" option; do
	case $option in
	o)
		tap_owner="$OPTARG"
		;;
	b)
		br_name="$OPTARG"
		;;
	a)
		br_addr="$OPTARG"
		;;
	h)
		_usage
		;;
	*)
		_usage "Invalid parameter"
		;;
	esac
done

[[ -z $br_name ]] \
	&& _usage "-b <bridge-name> or rapido.conf BR_DEV setting required"
[[ -z $tap_owner ]] \
	&& _usage "-o <tap-owner> or rapido.conf TAP_USER setting required"

tmpf=$(mktemp "rapido_tapdevs.XXXXXXX")
[[ -f $tmpf ]] || _fail "mktemp failed"

# cleanup on premature exit by executing whatever has been prepended to @unwind
unwind="rm \"$tmpf\""
trap "eval \$unwind" 0 1 2 3 15

_tap_manifest_gen "$tmpf" "$br_name"

# TODO proceed if it already exists
ip link add "$br_name" type bridge || _fail "failed to add $br_name"
unwind="ip link delete \"$br_name\" type bridge; $unwind"
echo -n "+ created bridge \"$br_name\""
if [[ -n $br_addr ]]; then
	ip addr add "$br_addr" dev "$br_name" || exit 1
	unwind="ip addr del \"$br_addr\" dev \"$br_name\"; $unwind"
	echo -n " with address \"$br_addr\""
fi

if [[ -n $BR_IF ]]; then
	# TODO: make BR_IF a script parameter too?
	ip link set "$BR_IF" master "$br_name" || exit 1
	unwind="ip link set \"$BR_IF\" nomaster; $unwind"
	echo -n ", connected to \"$BR_IF\""
fi
echo

# allow user to edit manifest prior to creation
if [[ -n $EDITOR ]]; then
	"$EDITOR" "$tmpf"
elif type -P vim &> /dev/null; then
	vim "$tmpf"
fi

tap_devs=()
mapfile -t tap_devs < <(grep -v -e "^#" -e "^$" "$tmpf")
for dev in "${tap_devs[@]}"; do
	# setup tap interfaces for VMs
	ip tuntap add dev "$dev" mode tap user "$tap_owner" \
		|| exit 1
	unwind="ip tuntap delete dev \"$dev\" mode tap; $unwind"
	ip link set "$dev" master "$br_name" || exit 1
	unwind="ip link set \"$dev\" nomaster; $unwind"
	echo "+ created \"$dev\""
done

for dev in "$br_name" "${tap_devs[@]}"; do
	ip link set dev "$dev" up || exit 1
	unwind="ip link set dev \"$dev\" down; $unwind"
done

if [[ -n $BR_DHCP_SRV_RANGE ]]; then
	# TODO deprecate in favour of networkd [DHCPServer] on vm
	dnsmasq --no-hosts --no-resolv \
		--pid-file=/var/run/rapido-dnsmasq-$$.pid \
		--bind-interfaces \
		--interface="$br_name" \
		--except-interface=lo \
		--dhcp-range="$BR_DHCP_SRV_RANGE" || exit 1
	unwind="kill $(cat /var/run/rapido-dnsmasq-$$.pid); ${unwind}"
	echo "+ started DHCP server on \"$br_name\""
fi

# success! clear unwind
unwind=""
