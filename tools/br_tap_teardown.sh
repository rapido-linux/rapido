#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2022, all rights reserved.

RAPIDO_DIR="$(realpath -e ${0%/*})/.."
. "${RAPIDO_DIR}/runtime.vars"

br_name="$BR_DEV"

_usage() {
	local err=$1
	local ret=0

	if [[ -n $err ]]; then
		echo -e "Error: $err\n"
		ret=1
	fi
	cat <<EOF
Usage: rapido teardown-network [OPTIONS]

OPTIONS:
  -b <bridge-name>: name of bridge device (default: rapido.conf BR_DEV)
  -h:               show this usage message
EOF
	exit "$ret"
}

_tap_manifest_gen() {
	manifest="$1"
	br_dev="$2"
	local i vm_tap

	[[ -d ${RAPIDO_DIR}/net-conf ]] \
		|| fail "net-conf directory missing, see net-conf.example"

	cat > "$manifest" << EOF
# The following tap devices will be deleted alongside "${br_dev}":
EOF
	shopt -s nullglob
	for i in ${RAPIDO_DIR}/net-conf/vm[0-9]*/*.network; do
		[[ $i =~ /vm[0-9]*/(.*)\.network$ ]] || continue
		vm_tap="${BASH_REMATCH[1]}"
		if [[ -d /sys/class/net/${vm_tap} ]]; then
			echo "$vm_tap" >> "$manifest"
		else
			echo "# \"$vm_tap\" does not exist" >> "$manifest"
		fi
	done
	cat >> "$manifest" << EOF

# Entries can be added or removed from the list above.
# Empty and '#' prefixed lines will be ignored. Exit to continue...
EOF
}

while getopts "b:h" option; do
	case $option in
	b)
		br_name="$OPTARG"
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

if [[ -n $BR_DHCP_SRV_RANGE ]]; then
	# FIXME should be able to use /var/run/rapido-dnsmasq-$$.pid
	dnsmasq_pid=`ps -eo pid,args | grep -v grep | grep dnsmasq \
			| grep -- --interface=$br_name \
			| grep -- --dhcp-range=$BR_DHCP_SRV_RANGE \
			| awk '{print $1}'`
	if [ -z "$dnsmasq_pid" ]; then
		echo "failed to find dnsmasq process"
		#exit 1
	else
		echo "+ stopping dnsmasq with pid: $dnsmasq_pid"
		kill "$dnsmasq_pid"
	fi
fi

tmpf=$(mktemp "rapido_tapdevs.XXXXXXX")
[[ -f $tmpf ]] || _fail "mktemp failed"
unwind="rm \"$tmpf\""
trap "eval \$unwind" 0 1 2 3 15

_tap_manifest_gen "$tmpf" "$br_name"

# allow user to edit manifest prior to destruction
if [[ -n $EDITOR ]]; then
	"$EDITOR" "$tmpf"
elif type -P vim &> /dev/null; then
	vim "$tmpf"
fi

tap_devs=()
mapfile -t tap_devs < <(grep -v -e "^#" -e "^$" "$tmpf")
for dev in "${tap_devs[@]}"; do
	echo "+ bringing down $dev"
	ip link set dev "$dev" down || _fail "failed to bring down $dev"
done

for dev in "${tap_devs[@]}"; do
	echo "+ deleting $dev"
	ip link set "$dev" nomaster || _fail "nomaster failed for $dev"
	ip tuntap delete dev "$dev" mode tap \
		|| _fail "deletion failed for $dev"
done

echo "+ deleting $br_name"
ip link delete $br_name type bridge || _fail "failed to remove $br_name"
