#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE S.A. 2022-2025, all rights reserved.
PATH="target/release:${PATH}"
rapido-cut --manifest /dev/stdin <<EOF
# order is currently important: all rsc paths need to be adjacently archived
file /rapido-rsc/cpu/1
file /rapido-rsc/mem/512M
# net.fest provides rapido-rsc/net path first...
include net.fest

autorun autorun/simple_network.sh $*

bin ps
bin nc
bin hostname
bin cat
bin ls
EOF
