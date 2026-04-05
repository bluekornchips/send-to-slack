#!/usr/bin/env bash
#
# Send to Slack script
# Processes JSON payload from stdin and sends message to Slack channel via API
# Supports Block Kit formatting, file uploads, and attachments
#

########################################################
# Default values
########################################################
SHOW_METADATA="true"
SHOW_PAYLOAD="true"

# Display usage information
#
# Side Effects:
# - Outputs usage message to stdout
#
# Returns:
# - 0 always
usage() {
	cat <<EOF
Usage: send-to-slack [OPTIONS]

Send messages to Slack using Block Kit formatting.

OPTIONS:
  -f, --file <path>     Read payload from file instead of stdin
  -v, --version         Display version information and exit
  -h, --help            Display this help message and exit
  --health-check        Validate dependencies and Slack API connectivity without sending

For more information, see: https://github.com/bluekornchips/send-to-slack
EOF
	return 0
}

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
	local version_path
	local version_value

	if [[ -z "$root_path" ]]; then
		return 1
	fi

	version_path="${root_path}/VERSION"

	if [[ -f "$version_path" ]]; then
		version_value=$(tr -d '\r' <"$version_path" | tr -d '\n')
		if [[ -n "$version_value" ]]; then
			echo "$version_value"
			return 0
		fi
	fi

	return 1
}

# Resolve commit from git metadata when available
#
# Inputs:
# - $1 - root_path: Base directory for repository or packaged copy
#
# Outputs:
# - Writes commit string to stdout on success
#
# Returns:
# - 0 on success, 1 on missing
get_commit() {
	local root_path="$1"
	local commit_value

	if [[ -z "$root_path" ]]; then
		return 1
	fi

	if command -v git >/dev/null 2>&1 && [[ -d "${root_path}/.git" ]]; then
		if commit_value=$(git -C "$root_path" rev-parse --short HEAD 2>/dev/null); then
			if [[ -n "$commit_value" ]]; then
				echo "$commit_value"
				return 0
			fi
		fi
	fi

	return 1
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
# - 0 always
print_version() {
	local root_path="$1"
	local version
	local commit
	local github_url="https://github.com/bluekornchips/send-to-slack"

	if ! version=$(get_version "$root_path"); then
		version="unknown"
	fi

	if ! commit=$(get_commit "$root_path"); then
		commit="unknown"
	fi

	echo "send-to-slack, (${github_url})"
	echo "version: ${version}"
	echo "commit: ${commit}"

	return 0
}

# Check for required external commands
#
# Returns:
#   0 if all dependencies are available
#   1 if any dependency is missing
check_dependencies() {
	local missing_deps=()
	local required_commands=("jq" "curl")

	for cmd in "${required_commands[@]}"; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			missing_deps+=("$cmd")
		fi
	done

	if [[ ${#missing_deps[@]} -gt 0 ]]; then
		echo "check_dependencies:: missing required dependencies: ${missing_deps[*]}" >&2
		echo "check_dependencies:: please install missing dependencies and try again" >&2
		return 1
	fi

	return 0
}

# Process input from stdin or from SEND_TO_SLACK_CLI_INPUT_FILE
#
# Arguments:
#   $1 - output_file: Path to write the input payload to
#
# Inputs:
# - SEND_TO_SLACK_CLI_INPUT_FILE: when set to a non-empty path, read that file
#
# Side Effects:
# - Writes input payload to output_file
# - May export SEND_TO_SLACK_INPUT_SOURCE=stdin
#
# Returns:
# - 0 on success
# - 1 on validation or read failure
process_input_to_file() {
	local output_file="$1"
	local input_file="${SEND_TO_SLACK_CLI_INPUT_FILE:-}"
	local use_stdin="false"

	if ! { touch "${output_file}" && chmod 0600 "${output_file}"; }; then
		echo "process_input_to_file:: failed to secure output file ${output_file}" >&2
		return 1
	fi

	if [[ -n "${input_file}" ]]; then
		if [[ ! -f "${input_file}" ]]; then
			echo "process_input_to_file:: input file does not exist: ${input_file}" >&2
			return 1
		fi
		use_stdin="false"
	else
		if [[ -t 0 ]]; then
			echo "process_input_to_file:: no input provided: use -f|--file <path> or provide input via stdin" >&2
			return 1
		fi
		use_stdin="true"
	fi

	echo "process_input_to_file:: reading input into ${output_file}" >&2

	if [[ "${use_stdin}" == "true" ]]; then
		if ! cat >"${output_file}"; then
			echo "process_input_to_file:: failed to read from stdin" >&2
			return 1
		fi
		if [[ ! -s "${output_file}" ]]; then
			echo "process_input_to_file:: no input received on stdin" >&2
			return 1
		fi
	else
		if ! cat -- "${input_file}" >"${output_file}"; then
			echo "process_input_to_file:: failed to read input file: ${input_file}" >&2
			ls -l "${input_file}" >&2
			return 1
		fi
		if [[ ! -s "${output_file}" ]]; then
			echo "process_input_to_file:: input file is empty: ${input_file}" >&2
			return 1
		fi
	fi

	if [[ "${use_stdin}" == "true" ]]; then
		export SEND_TO_SLACK_INPUT_SOURCE="stdin"
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

	script_path="${BASH_SOURCE[0]}"
	if [[ -L "$script_path" ]]; then
		script_path=$(readlink -f "$script_path" 2>/dev/null || readlink "$script_path")
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

	echo "find_root_dir:: cannot locate lib/parse/payload.sh (checked: ${script_dir}, ${parent_dir})" >&2

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
		echo "initialize_script_environment:: cannot locate lib/parse/payload.sh (lib_dir: ${lib_dir})" >&2
		return 1
	fi

	echo "$root_dir"

	return 0
}

# Parse command line arguments
#
# Arguments:
#   $@ - Command line arguments
#
# Side Effects:
#   Sets health_check_mode, SEND_TO_SLACK_CLI_INPUT_FILE, clears main_args then fills it
#
# Returns:
#   0 on success
#   1 on parse error
#   2 if version or help was requested
parse_main_args() {
	main_args=()
	health_check_mode=false
	SEND_TO_SLACK_CLI_INPUT_FILE=""

	while [[ $# -gt 0 ]]; do
		case $1 in
		-v | --version)
			local root_dir
			if ! root_dir=$(find_root_dir); then
				echo "parse_main_args:: cannot determine root directory" >&2
				return 1
			fi
			print_version "$root_dir"
			return 2
			;;
		-h | --help)
			usage
			return 2
			;;
		--health-check)
			health_check_mode=true
			shift
			;;
		-f | -file | --file)
			if [[ -n "${SEND_TO_SLACK_CLI_INPUT_FILE}" ]]; then
				echo "parse_main_args:: -f|-file|--file option can only be specified once" >&2
				return 1
			fi
			if [[ $# -lt 2 ]]; then
				echo "parse_main_args:: -f|-file|--file requires a file path argument" >&2
				return 1
			fi
			SEND_TO_SLACK_CLI_INPUT_FILE="$2"
			shift 2
			;;
		*)
			echo "parse_main_args:: unknown option: $1" >&2
			echo "parse_main_args:: use -h for usage" >&2
			return 1
			;;
		esac
	done

	export SEND_TO_SLACK_CLI_INPUT_FILE

	return 0
}

# Create temp workspace and register cleanup trap
#
# Side Effects:
# - Sets and exports _SLACK_WORKSPACE
# - Installs EXIT and ERR trap to remove the directory
#
# Returns:
# - 0 on success
# - 1 if mktemp fails
init_slack_workspace() {
	_SLACK_WORKSPACE=$(mktemp -d "${TMPDIR:-/tmp}/send-to-slack.run.XXXXXX")
	if [[ -z "${_SLACK_WORKSPACE}" ]]; then
		echo "init_slack_workspace:: mktemp failed" >&2
		return 1
	fi
	export _SLACK_WORKSPACE
	trap 'rm -rf "$_SLACK_WORKSPACE"' EXIT ERR

	return 0
}

# UTC timestamp for Concourse version JSON
#
# Outputs:
# - ISO-like UTC timestamp string
#
# Returns:
# - 0 always
get_timestamp_utc() {
	date -u +%Y-%m-%dT%H:%M:%SZ

	return 0
}

# Apply params.debug overrides to logging globals
#
# Inputs:
# - $1 - input_payload: path to raw input JSON
#
# Side Effects:
# - May set SHOW_METADATA, SHOW_PAYLOAD, LOG_VERBOSE
#
# Returns:
# - 0 always
apply_debug_from_payload() {
	local input_payload="$1"
	local debug_enabled

	debug_enabled=$(jq -r '.params.debug // false' "${input_payload}")
	if [[ "$debug_enabled" == "true" ]]; then
		SHOW_METADATA="true"
		SHOW_PAYLOAD="true"
		export SHOW_METADATA
		export SHOW_PAYLOAD
		export LOG_VERBOSE="true"
	fi

	return 0
}

# Emit Concourse resource JSON to stdout or SEND_TO_SLACK_OUTPUT
#
# Inputs:
# - $1 - timestamp: version.timestamp string
# - $2 - meta_ts: message ts for version.message_ts when non-empty
#
# Inputs from environment:
# - METADATA: JSON value for metadata field
# - SEND_TO_SLACK_OUTPUT: optional file path
#
# Returns:
# - 0 on success
# - 1 if jq fails
emit_concourse_output() {
	local timestamp="$1"
	local meta_ts="$2"
	local json_output

	if ! json_output=$(jq -n \
		--arg timestamp "${timestamp}" \
		--arg version_message_ts "${meta_ts}" \
		--argjson metadata "${METADATA}" \
		'{
      version: (
        if $version_message_ts != "" then { timestamp: $timestamp, message_ts: $version_message_ts }
        else { timestamp: $timestamp }
        end
      ),
      metadata: $metadata
    }'); then
		echo "emit_concourse_output:: failed to build output JSON" >&2
		return 1
	fi

	if [[ -n "${SEND_TO_SLACK_OUTPUT:-}" ]]; then
		jq -r '.' <<<"${json_output}" >"${SEND_TO_SLACK_OUTPUT}"
		echo "main:: output written to ${SEND_TO_SLACK_OUTPUT}"
	else
		jq -r '.' <<<"${json_output}"
	fi

	return 0
}

# Source API, metadata, and mention resolution libraries
#
# Inputs:
# - $1 - root_dir: repository or install root
#
# Returns:
# - 0 on success
# - 1 if a required file is missing
source_send_to_slack_libs_core() {
	local root_dir="$1"
	local path

	for path in \
		"${root_dir}/lib/slack/api.sh" \
		"${root_dir}/lib/metadata.sh" \
		"${root_dir}/lib/slack/utils/resolve-mentions.sh"; do
		if [[ ! -f "$path" ]]; then
			echo "main:: cannot locate required library at ${path}" >&2
			return 1
		fi
		# shellcheck disable=SC1090
		source "$path"
	done

	return 0
}

# Source payload parsing, crosspost, and replies libraries
#
# Inputs:
# - $1 - root_dir: repository or install root
#
# Returns:
# - 0 on success
# - 1 if a required file is missing
source_send_to_slack_libs_message() {
	local root_dir="$1"
	local path

	for path in \
		"${root_dir}/lib/parse/payload.sh" \
		"${root_dir}/lib/slack/crosspost.sh" \
		"${root_dir}/lib/slack/replies.sh"; do
		if [[ ! -f "$path" ]]; then
			echo "main:: cannot locate required library at ${path}" >&2
			return 1
		fi
		# shellcheck disable=SC1090
		source "$path"
	done

	return 0
}

# Main entry point that processes stdin payload and sends to Slack
#
# Inputs:
# - Reads JSON payload from stdin or from file specified with -f|--file
#
# Side Effects:
# - Sends message to Slack API
# - Outputs informational messages to stdout for logging
# - Outputs JSON to stdout at the end unless SEND_TO_SLACK_OUTPUT is set
#
# Returns:
# - 0 on successful message delivery and output generation
# - 1 if payload parsing, metadata creation, or notification sending fails
main() {
	local input_payload
	local timestamp
	local root_dir
	local parse_result
	local update_rc

	if ! root_dir=$(initialize_script_environment); then
		return 1
	fi

	parse_result=0
	parse_main_args "$@" || parse_result=$?

	if [[ "$parse_result" -eq 2 ]]; then
		return 0
	fi

	if [[ "$parse_result" -ne 0 ]]; then
		echo "main:: failed to parse arguments" >&2
		return 1
	fi

	if [[ ! -f "${root_dir}/lib/health-check.sh" ]]; then
		echo "main:: cannot locate health-check.sh at ${root_dir}/lib/health-check.sh" >&2
		return 1
	fi
	# shellcheck disable=SC1091
	source "${root_dir}/lib/health-check.sh"

	local version
	if ! version=$(get_version "$root_dir"); then
		version="unknown"
	fi
	echo "main:: send-to-slack ${version}"

	if [[ "$health_check_mode" == "true" ]]; then
		if ! health_check; then
			return 1
		fi
		return 0
	fi

	# Install root for lib helpers, lib/parse/payload.sh and Block Kit expect this before load
	SEND_TO_SLACK_ROOT="$root_dir"
	export SEND_TO_SLACK_ROOT

	if ! source_send_to_slack_libs_core "${root_dir}"; then
		return 1
	fi

	export METADATA
	export SHOW_METADATA
	export SHOW_PAYLOAD

	if ! check_dependencies; then
		return 1
	fi

	echo "main:: starting task to send notification to Slack from Concourse"

	if ! init_slack_workspace; then
		return 1
	fi

	input_payload="${_SLACK_WORKSPACE}/input_payload"

	if ! process_input_to_file "${input_payload}"; then
		echo "main:: failed to process input" >&2
		return 1
	fi

	timestamp=$(get_timestamp_utc)

	apply_debug_from_payload "${input_payload}"

	if [[ -n "${SEND_TO_SLACK_INPUT_SOURCE:-}" ]]; then
		echo "main:: input source: ${SEND_TO_SLACK_INPUT_SOURCE}" >&2
	fi

	echo "main:: parsing payload"

	if [[ ! -f "${input_payload}" ]]; then
		echo "main:: input file disappeared before parsing: ${input_payload}" >&2
		return 1
	fi

	if ! source_send_to_slack_libs_message "${root_dir}"; then
		return 1
	fi

	local parsed_payload_file
	parsed_payload_file="${_SLACK_WORKSPACE}/parsed_payload"
	if ! parse_payload "${input_payload}" >"${parsed_payload_file}"; then
		echo "main:: failed to parse payload" >&2
		return 1
	fi
	local parsed_payload
	parsed_payload=$(cat "${parsed_payload_file}")
	rm -f "${parsed_payload_file}"

	update_rc=0
	run_chat_update_from_input "${input_payload}" "${parsed_payload}" || update_rc=$?

	if [[ "$update_rc" -eq 1 ]]; then
		return 1
	fi

	if [[ "$update_rc" -eq 0 ]]; then
		:
	elif [[ "$update_rc" -eq 2 ]]; then
		echo "main:: sending notification"
		if ! send_notification "$parsed_payload"; then
			echo "main:: failed to send notification" >&2
			return 1
		fi

		if [[ "${DELIVERY_METHOD:-api}" == "api" ]]; then
			if [[ -n "${EPHEMERAL_USER:-}" ]]; then
				echo "main:: chat.postEphemeral does not support thread replies or crosspost, skipping send_thread_replies and crosspost_notification" >&2
			else
				local primary_ts
				if [[ -n "${RESPONSE:-}" ]] && jq . >/dev/null 2>&1 <<<"$RESPONSE"; then
					primary_ts=$(echo "$RESPONSE" | jq -r '.ts // empty')
				else
					primary_ts=""
				fi

				local reply_thread_ts
				reply_thread_ts=$(echo "$parsed_payload" | jq -r '.thread_ts // empty')
				if [[ -z "$reply_thread_ts" || "$reply_thread_ts" == "null" ]]; then
					reply_thread_ts="${primary_ts:-}"
				fi

				if ! send_thread_replies "${input_payload}" "$reply_thread_ts" "$parsed_payload"; then
					echo "main:: send_thread_replies encountered failures, continuing" >&2
				fi

				if ! crosspost_notification "${input_payload}"; then
					echo "main:: failed to crosspost notification" >&2
					return 1
				fi
			fi
		else
			echo "main:: delivery method webhook does not support thread replies, skipping send_thread_replies" >&2
			echo "main:: delivery method webhook does not support crosspost, skipping crosspost_notification" >&2
		fi
	else
		echo "main:: unexpected run_chat_update_from_input exit code: ${update_rc}" >&2
		return 1
	fi

	local meta_ts=""
	local meta_ch=""
	if [[ -n "${RESPONSE:-}" ]] && jq . >/dev/null 2>&1 <<<"$RESPONSE"; then
		meta_ts=$(echo "$RESPONSE" | jq -r '.ts // empty')
		meta_ch=$(echo "$RESPONSE" | jq -r '.channel // empty')
	fi

	[[ "$meta_ts" == "null" ]] && meta_ts=""
	[[ "$meta_ch" == "null" ]] && meta_ch=""

	echo "main:: creating Concourse metadata"
	if ! create_metadata "$parsed_payload" "$meta_ts" "$meta_ch"; then
		echo "main:: failed to create metadata" >&2
		return 1
	fi

	if ! emit_concourse_output "${timestamp}" "${meta_ts}"; then
		return 1
	fi

	echo "main:: finished running send-to-slack.sh successfully"

	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	set -eo pipefail
	umask 077
	main "$@"
	exit $?
fi
