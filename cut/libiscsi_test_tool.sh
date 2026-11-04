#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE S.A. 2026, all rights reserved.
rapido-cut --manifest /dev/stdin <<EOF
file /rapido-rsc/mem/512M
include net.fest

autorun autorun/libiscsi_test_tool.sh $*

bin \${LIBISCSI_SRC}/test-tool/iscsi-test-cu
bin cat
bin find
bin grep
bin hostname
bin ls
bin nc
bin ps
EOF
