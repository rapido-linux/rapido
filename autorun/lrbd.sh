#!/bin/bash
#
# Copyright (C) SUSE LINUX GmbH 2018, all rights reserved.
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

# autorun scripts are run immediately once the Rapido scratch VM has booted...

# protect against running (harmful) scripts outside of Rapido VMs
_vm_ar_env_check || exit 1

# explitly load LIO core only, see dbroot comment below...
modprobe target_core_mod

_vm_ar_dyn_debug_enable

sed -i "s#keyring = .*#keyring = /etc/ceph/keyring#g; \
	s#admin socket = .*##g; \
	s#run dir = .*#run dir = /var/run/#g; \
	s#log file = .*#log file = /var/log/\$name.\$pid.log#g" \
	/etc/ceph/ceph.conf

set -x

ln -s /usr/bin/python3 /usr/bin/python || _fatal

for i in rtslib configshell targetcli; do
	cd "/${i}" || _fatal	# need to account for version suffix
	./setup.py build || _fatal
	./setup.py install || _fatal
done

cd /
mkdir -p /etc/target/backup

# FIXME rtslib attempts to change dbroot to /etc/target (_preferred_dbroot), but
# this fails after other drivers are loaded (db_root: cannot be changed: target
# drivers registered). Do it now manually instead...
echo -n /etc/target > /sys/kernel/config/target/dbroot

ln -s "${CEPH_SRC}/build/bin/rbd" /bin/rbd
ln -s "${CEPH_SRC}/build/lib/cython_modules/lib.3/rados.cpython-34m.so" \
	/usr/lib64/python3.4/
echo "${CEPH_SRC}/build/lib/" >> /etc/ld.so.conf.d/rapido.conf || _fatal
ldconfig || _fatal

# run dbusd as root instead of messagebus. Daemon needed by targetcli
sed -i "s#<user>\\w*</user>#<user>root</user>#" /etc/dbus-1/system.conf
mkdir -p /run/dbus/ /etc/dbus-1/system.d
dbus-daemon --system || _fatal

cat > lrbd.conf.json << EOF
{
  "auth": [
        {
          "target": "$TARGET_IQN",
          "authentication": "none"
        }
  ],
  "targets": [
      {
        "hosts": [
            { "host": "$HOSTNAME1", "portal": "portal1" },
            { "host": "$HOSTNAME2", "portal": "portal2" }
        ],
        "target": "$TARGET_IQN"
      }
  ],
  "portals": [
      {
          "name": "portal1",
          "addresses": [ "$IP_ADDR1" ]
      },
      {
          "name": "portal2",
          "addresses": [ "$IP_ADDR2"  ]
      }
  ],
  "pools": [
    {
      "pool": "$CEPH_RBD_POOL",
      "gateways": [
        {
          "target": "$TARGET_IQN",
          "tpg": [
            {
              "image": "$CEPH_RBD_IMAGE"
            }
          ]
        }
      ]
    }
  ]
}
EOF

lrbd -f lrbd.conf.json || _fatal
set +x
lrbd -d || _fatal
