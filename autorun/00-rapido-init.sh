# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2020-2024, all rights reserved.

# This script runs as the first Dracut entry point during /init.
# $DRACUT_SYSTEMD is set when run via systemd.

_ctty=
for i in $(cat /proc/cmdline); do
	case "$i" in
		"console="*)
			_ctty="/dev/${i#console=}"
			break
			;;
	esac
done
[ -c "$_ctty" ] || _ctty=/dev/tty1

setsid --ctty -- /bin/bash --rcfile /rapido.rc -i 0<>$_ctty 1<>$_ctty 2<>$_ctty

# shut down when rapido autorun / shell exits...
echo 1 > /proc/sys/kernel/sysrq && echo o > /proc/sysrq-trigger
sleep 20
