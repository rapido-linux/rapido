#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE S.A. 2022-2025, all rights reserved.
fest="$(mktemp --tmpdir fest.XXXXX)"
trap "rm \"$fest\"" 0
cat > "$fest" <<EOF
# order is currently important: all rsc paths need to be adjacently archived
file /rapido-rsc/cpu/1 dracut.conf.d/.empty
file /rapido-rsc/mem/512M dracut.conf.d/.empty
# net.fest provides rapido-rsc/net path first...
include net.fest

autorun autorun/simple_network.sh $*

bin ps
bin nc
bin hostname
bin cat
bin ls
EOF

PATH="target/release:${PATH}"
rapido-cut --manifest "$fest"
