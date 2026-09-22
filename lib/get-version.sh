#!/usr/bin/env bash
#
# Resolve CLI version from VERSION file for send-to-slack
# Source this file from send-to-slack.sh, do not execute directly
#

GITHUB_URL="https://github.com/bluekornchips/send-to-slack"

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

# Resolve short git commit from repository root when available
#
# Inputs:
# - $1 - root_path: Base directory for repository or packaged copy
#
# Outputs:
# - Writes commit hash to stdout on success
#
# Returns:
# - 0 on success, 1 on missing
get_commit() {
	local root_path="$1"
	[[ -z "$root_path" ]] && return 1

	local commit_value
	if ! command -v git >/dev/null 2>&1; then
		return 1
	fi

	if [[ ! -e "${root_path}/.git" ]]; then
		return 1
	fi

	if ! commit_value=$(git -C "$root_path" rev-parse --short HEAD 2>/dev/null); then
		return 1
	fi

	if [[ -z "$commit_value" ]]; then
		echo "get_commit:: failed to get commit" >&2
		return 1
	fi

	echo "$commit_value"

	return 0
}

# Print version information for CLI output
#
# Inputs:
# - $1 - root_path: Base directory for repository or packaged copy
#
# Outputs:
# - Writes version info to stdout
#
# Returns:
# - 0 on success, 1 if root_path is empty
print_version() {
	local root_path="$1"
	[[ -z "$root_path" ]] && return 1

	local version
	if ! version=$(get_version "$root_path"); then
		version="unknown"
	fi

	local commit
	if ! commit=$(get_commit "$root_path"); then
		commit="unknown"
	fi

	cat <<EOF
send-to-slack, (${GITHUB_URL})
version: ${version}
commit: ${commit}
EOF

	return 0
}
