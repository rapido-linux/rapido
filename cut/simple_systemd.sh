#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE S.A. 2026, all rights reserved.

# This matches simple-example, except that it includes the systemd manifest and
# example service.

PATH="target/release:${PATH}"
rapido-cut --manifest /dev/stdin <<EOF
autorun autorun/simple_example.sh $*

include systemd.fest
# bundle our own service file
file /usr/lib/systemd/system/simple-example.service systemd/simple-example.service
# ensure that the service runs as part of the default rapido-init.target
slink /usr/lib/systemd/system/rapido-init.target.wants/simple-example.service ../simple-example.service

bin cat
bin chmod
bin dd
bin ls
bin mkdir
bin ps
bin rm
bin rmdir
bin sleep
bin touch
try-bin nano
EOF
