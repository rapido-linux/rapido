#!/bin/bash
# SPDX-License-Identifier: (LGPL-2.1 OR LGPL-3.0)
# Copyright (C) SUSE LLC 2023, all rights reserved.

_samba_paths_init() {
	local conf_file="$1" state="search" d=() key dir
	[ -n "$SAMBA_SRC" ] && export PATH="${SAMBA_SRC}/bin/:${PATH}"

	while [[ $state != "end" ]] && read -r key dir; do
		if [[ $key == "Paths:" ]]; then
			state="paths"
			continue
		fi
		[[ $state == "paths" ]] || continue;
		case "$key" in
		"")
			state="end"
			;;
		LOGFILEBASE:)
			echo "Log at: ${dir}/log.smbd"
			d+=("$dir")
			;;
		*DIR:)
			if [[ $key == "MODULESDIR:" && -d "$SAMBA_SRC" ]]; then
			    ln -s "${SAMBA_SRC}/bin/modules/vfs/" "${dir}/vfs" \
				|| _fatal "failed to symlink vfs modules"
			fi
			d+=("$dir")
			;;
		esac
	done < <(smbd -b -s "$conf_file") \
		|| _fatal "failed to get smbd build options"
	(( ${#d[*]} > 0 )) && mkdir -p "${d[@]}"
}
