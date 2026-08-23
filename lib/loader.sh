#!/usr/bin/env bash
#
# Root discovery and explicit library loading for send-to-slack
# Source this file from send-to-slack.sh before calling _load_libs
#

# Ordered library manifest relative to lib/. parse/blocks.sh must remain last.
SEND_TO_SLACK_LIB_MANIFEST=(
	"get-version.sh"
	"cli.sh"
	"health-check.sh"
	"runtime.sh"
	"metadata.sh"
	"parse/payload.sh"
	"slack/api.sh"
	"slack/derived-payload.sh"
	"slack/utils/resolve-mentions.sh"
	"slack/utils/file-upload.sh"
	"slack/block-kit/create-block.sh"
	"slack/crosspost.sh"
	"slack/replies.sh"
	"delivery.sh"
	"parse/blocks.sh"
)

# Source a file and propagate non-zero status immediately
#
# Arguments:
#   $1 - path to shell module
#
# Returns:
# - 0 on success
# - 1 if the file is missing or source fails
source_required() {
	local module_path="$1"

	if [[ ! -f "$module_path" ]]; then
		echo "source_required:: missing module: ${module_path}" >&2
		return 1
	fi

	# shellcheck disable=SC1090,SC1091
	if ! source "$module_path"; then
		echo "source_required:: failed to source: ${module_path}" >&2
		return 1
	fi

	return 0
}

# Find the root directory of the send-to-slack source bundle
#
# Outputs:
#   Writes root_dir path to stdout
#
# Returns:
#   0 on success
#   1 if root directory cannot be located
find_root_dir() {
	local script_path
	local script_dir
	local parent_dir
	local link_target

	script_path="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"

	if [[ -L "$script_path" ]]; then
		link_target=$(readlink "$script_path" 2>/dev/null || true)
		if [[ -z "$link_target" || "$link_target" != /* ]]; then
			echo "find_root_dir:: expected absolute symlink target at ${script_path}" >&2
			return 1
		fi
		script_path="$link_target"
	fi

	script_dir=$(cd "$(dirname "$script_path")" && pwd)
	if [[ -z "$script_dir" ]]; then
		echo "find_root_dir:: cannot determine script directory" >&2
		return 1
	fi

	parent_dir=$(cd "${script_dir}/.." && pwd)

	if [[ -f "${script_dir}/lib/parse/payload.sh" ]]; then
		echo "$script_dir"
		return 0
	fi

	if [[ -n "$parent_dir" && -f "${parent_dir}/lib/parse/payload.sh" ]]; then
		echo "$parent_dir"
		return 0
	fi

	echo "find_root_dir:: cannot locate lib/parse/payload.sh (checked:" \
		"${script_dir}, ${parent_dir})" >&2

	return 1
}

# Initialize script environment and locate root directory
#
# Outputs:
#   Writes root_dir path to stdout
#
# Returns:
#   0 on success
#   1 if root directory cannot be located
initialize_script_environment() {
	local root_dir
	local lib_dir

	if ! root_dir=$(find_root_dir); then
		return 1
	fi

	lib_dir="${root_dir}/lib"

	if [[ ! -f "${lib_dir}/parse/payload.sh" ]]; then
		echo "initialize_script_environment:: cannot locate lib/parse/payload.sh" \
			"(lib_dir: ${lib_dir})" >&2
		return 1
	fi

	echo "$root_dir"

	return 0
}

# Source library modules from SEND_TO_SLACK_LIB_MANIFEST in order
#
# Inputs:
# - $1 - root_dir: repository or install root
#
# Side Effects:
# - SEND_TO_SLACK_ROOT must already be set and exported before calling
#
# Returns:
# - 0 on success
# - 1 if lib is missing, a file is missing, or source fails
_load_libs() {
	local root_dir="$1"
	local lib_root
	local rel
	local abs

	[[ -z "$root_dir" ]] && return 1

	lib_root="${root_dir}/lib"
	if [[ ! -d "$lib_root" ]]; then
		echo "_load_libs:: lib directory not found: ${lib_root}" >&2
		return 1
	fi

	for rel in "${SEND_TO_SLACK_LIB_MANIFEST[@]}"; do
		abs="${lib_root}/${rel}"
		if ! source_required "$abs"; then
			return 1
		fi
	done

	return 0
}
