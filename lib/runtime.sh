#!/usr/bin/env bash
#
# Input, workspace, and debug helpers for a send-to-slack run
# Source this file from send-to-slack.sh, do not execute directly
#

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
	if ! { touch "${output_file}" && chmod 0600 "${output_file}"; }; then
		echo "process_input_to_file:: failed to secure output file ${output_file}" >&2
		return 1
	fi

	local use_stdin="false"
	local input_file="${SEND_TO_SLACK_CLI_INPUT_FILE:-}"
	if [[ -n "${input_file}" ]]; then
		if [[ ! -f "${input_file}" ]]; then
			echo "process_input_to_file:: input file does not exist: ${input_file}" >&2
			return 1
		fi
		use_stdin="false"
	else
		if [[ -t 0 ]]; then
			echo "process_input_to_file:: no input provided: use -f|--file <path> or" \
				"provide input via stdin" >&2
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
		SEND_TO_SLACK_INPUT_SOURCE="stdin"
		export SEND_TO_SLACK_INPUT_SOURCE
	fi

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
# - 0 on success, 1 if input_payload path is empty
apply_debug_from_payload() {
	local input_payload="$1"
	[[ -z "$input_payload" ]] && return 1

	local debug_enabled
	debug_enabled=$(jq -r '.params.debug // false' "${input_payload}")
	if [[ "$debug_enabled" == "true" ]]; then
		SHOW_METADATA="true"
		SHOW_PAYLOAD="true"
		LOG_VERBOSE="true"
		export SHOW_METADATA
		export SHOW_PAYLOAD
		export LOG_VERBOSE
	fi

	return 0
}
