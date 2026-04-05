#!/usr/bin/env bash
#
# Resolve CLI version from VERSION file for send-to-slack
# Source this file from send-to-slack.sh, do not execute directly
#

# Resolve version from known locations
#
# Inputs:
# - $1 - root_path: Base directory for repository or packaged copy
#
# Outputs:
# - Writes version string to stdout on success
#
# Returns:
# - 0 on success, 1 on missing
get_version() {
	local root_path="$1"
	[[ -z "$root_path" ]] && return 1

	local version_path="${root_path}/VERSION"

	if [[ -f "$version_path" ]]; then
		local version_value
		version_value=$(tr -d '\r' <"$version_path" | tr -d '\n')
		if [[ -n "$version_value" ]]; then
			echo "$version_value"
			return 0
		fi
	fi

	return 1
}
