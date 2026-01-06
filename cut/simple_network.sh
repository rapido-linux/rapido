#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE S.A. 2022-2025, all rights reserved.

PATH="target/release:${PATH}"
rapido-cut \
	--autorun "autorun/simple_network.sh $*" \
	--install "ps nc hostname cat ls" \
	--manifest net.fest \
	--include "dracut.conf.d/.empty /rapido-rsc/cpu/1" \
	--include "dracut.conf.d/.empty /rapido-rsc/mem/512M"
