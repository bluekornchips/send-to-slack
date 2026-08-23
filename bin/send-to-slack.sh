#!/usr/bin/env bash
# shellcheck source=lib/loader.sh
# shellcheck source=lib/cli.sh
# shellcheck source=lib/delivery.sh
# shellcheck source=lib/get-version.sh
# shellcheck source=lib/health-check.sh
# shellcheck source=lib/metadata.sh
# shellcheck source=lib/parse/payload.sh
# shellcheck source=lib/runtime.sh
#
# Send to Slack script
# Processes JSON payload from stdin and sends message to Slack channel via API
# Supports Block Kit formatting, file uploads, and attachments
#
# Library loading lives in lib/loader.sh. Helpers are loaded from an explicit
# manifest.
#

########################################################
# Default values
########################################################
SHOW_METADATA="true"
SHOW_PAYLOAD="true"

# Locate and source loader helpers before loading the rest of lib/
#
# Returns:
# - 0 on success
# - 1 if loader cannot be located
_source_loader() {
	local script_path
	local script_dir
	local parent_dir
	local candidate

	script_path="${BASH_SOURCE[0]}"
	if [[ -L "$script_path" ]]; then
		local link_target
		link_target=$(readlink "$script_path" 2>/dev/null || true)
		if [[ -z "$link_target" || "$link_target" != /* ]]; then
			echo "_source_loader:: expected absolute symlink target at" \
				"${script_path}" >&2
			return 1
		fi
		script_path="$link_target"
	fi

	script_dir=$(cd "$(dirname "$script_path")" && pwd)
	parent_dir=$(cd "${script_dir}/.." && pwd)

	for candidate in "${script_dir}/lib/loader.sh" \
		"${parent_dir}/lib/loader.sh"; do
		if [[ -f "$candidate" ]]; then
			# shellcheck source=lib/loader.sh disable=SC1090,SC1091
			source "$candidate"
			return 0
		fi
	done

	echo "_source_loader:: cannot locate lib/loader.sh" >&2
	return 1
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

	if ! _source_loader; then
		return 1
	fi

	# shellcheck source=lib/loader.sh
	if ! root_dir=$(initialize_script_environment); then
		return 1
	fi

	SEND_TO_SLACK_ROOT="$root_dir"
	export SEND_TO_SLACK_ROOT

	# shellcheck source=lib/loader.sh
	if ! _load_libs "${root_dir}"; then
		return 1
	fi

	health_check_mode=false
	parse_result=0
	# shellcheck source=lib/cli.sh
	parse_main_args "$root_dir" "$@" || parse_result=$?

	if [[ "$parse_result" -eq 2 ]]; then
		return 0
	fi

	if [[ "$parse_result" -ne 0 ]]; then
		echo "main:: failed to parse arguments" >&2
		return 1
	fi

	local version
	# shellcheck source=lib/get-version.sh
	if ! version=$(get_version "$root_dir"); then
		version="unknown"
	fi
	echo "main:: send-to-slack ${version}"

	if [[ "$health_check_mode" == "true" ]]; then
		# shellcheck source=lib/health-check.sh
		if ! health_check; then
			return 1
		fi
		return 0
	fi

	export METADATA
	export SHOW_METADATA
	export SHOW_PAYLOAD

	# shellcheck source=lib/health-check.sh
	if ! require_runtime_commands; then
		return 1
	fi

	echo "main:: starting task to send notification to Slack from Concourse"

	# shellcheck source=lib/runtime.sh
	if ! init_slack_workspace; then
		return 1
	fi

	input_payload="${_SLACK_WORKSPACE}/input_payload"

	# shellcheck source=lib/runtime.sh
	if ! process_input_to_file "${input_payload}"; then
		echo "main:: failed to process input" >&2
		return 1
	fi

	# shellcheck source=lib/runtime.sh
	timestamp=$(get_timestamp_utc)

	# shellcheck source=lib/runtime.sh
	apply_debug_from_payload "${input_payload}"

	if [[ -n "${SEND_TO_SLACK_INPUT_SOURCE:-}" ]]; then
		echo "main:: input source: ${SEND_TO_SLACK_INPUT_SOURCE}" >&2
	fi

	echo "main:: parsing payload"

	if [[ ! -f "${input_payload}" ]]; then
		echo "main:: input file disappeared before parsing: ${input_payload}" >&2
		return 1
	fi

	local parsed_payload_file
	parsed_payload_file="${_SLACK_WORKSPACE}/parsed_payload"
	# shellcheck source=lib/parse/payload.sh
	if ! parse_payload "${input_payload}" >"${parsed_payload_file}"; then
		echo "main:: failed to parse payload" >&2
		return 1
	fi
	local parsed_payload
	parsed_payload=$(cat "${parsed_payload_file}")
	rm -f "${parsed_payload_file}"

	# shellcheck source=lib/delivery.sh
	if ! run_delivery_from_input "${input_payload}" "${parsed_payload}"; then
		return 1
	fi

	local meta_ts meta_ch
	# shellcheck source=lib/delivery.sh
	meta_ts=$(_response_field "ts")
	# shellcheck source=lib/delivery.sh
	meta_ch=$(_response_field "channel")

	echo "main:: creating Concourse metadata"
	# shellcheck source=lib/metadata.sh
	if ! create_metadata "$parsed_payload" "$meta_ts" "$meta_ch"; then
		echo "main:: failed to create metadata" >&2
		return 1
	fi

	# shellcheck source=lib/metadata.sh
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
