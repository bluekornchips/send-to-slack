#!/usr/bin/env bats
#
# Tests for lib/runtime.sh
#

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		fail "Failed to get git root"
	fi

	LIB="$GIT_ROOT/lib/runtime.sh"
	if [[ ! -f "$LIB" ]]; then
		fail "Script not found: $LIB"
	fi

	export GIT_ROOT
	export LIB

	return 0
}

setup() {
	source "$LIB"
	unset SEND_TO_SLACK_CLI_INPUT_FILE
	unset SEND_TO_SLACK_INPUT_SOURCE
	unset SHOW_METADATA
	unset SHOW_PAYLOAD
	unset LOG_VERBOSE

	return 0
}

@test "get_timestamp_utc:: prints ISO-like UTC timestamp" {
	run get_timestamp_utc
	[[ "$status" -eq 0 ]]
	[[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "apply_debug_from_payload:: fails when path is empty" {
	run apply_debug_from_payload ""
	[[ "$status" -eq 1 ]]
}

@test "apply_debug_from_payload:: leaves globals unset when debug is false" {
	local payload
	payload=$(mktemp "${BATS_TEST_TMPDIR}/runtime-debug-false.XXXXXX")
	printf '%s\n' '{"params":{"debug":false}}' >"$payload"

	if ! apply_debug_from_payload "$payload"; then
		return 1
	fi
	[[ -z "${SHOW_METADATA:-}" ]]
	[[ -z "${LOG_VERBOSE:-}" ]]
}

@test "apply_debug_from_payload:: enables logging globals when debug is true" {
	local payload
	payload=$(mktemp "${BATS_TEST_TMPDIR}/runtime-debug-true.XXXXXX")
	printf '%s\n' '{"params":{"debug":true}}' >"$payload"

	if ! apply_debug_from_payload "$payload"; then
		return 1
	fi
	[[ "$SHOW_METADATA" == "true" ]]
	[[ "$SHOW_PAYLOAD" == "true" ]]
	[[ "$LOG_VERBOSE" == "true" ]]
}

@test "process_input_to_file:: copies SEND_TO_SLACK_CLI_INPUT_FILE" {
	local input_file
	local output_file
	input_file=$(mktemp "${BATS_TEST_TMPDIR}/runtime-input.XXXXXX")
	output_file=$(mktemp "${BATS_TEST_TMPDIR}/runtime-output.XXXXXX")
	printf '%s\n' '{"ok":true}' >"$input_file"
	SEND_TO_SLACK_CLI_INPUT_FILE="$input_file"

	run process_input_to_file "$output_file"
	[[ "$status" -eq 0 ]]
	[[ "$(cat "$output_file")" == '{"ok":true}' ]]
}

@test "process_input_to_file:: fails when input file is missing" {
	local output_file
	output_file=$(mktemp "${BATS_TEST_TMPDIR}/runtime-output-missing.XXXXXX")
	SEND_TO_SLACK_CLI_INPUT_FILE="${BATS_TEST_TMPDIR}/does-not-exist.json"

	run process_input_to_file "$output_file"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "input file does not exist"
}

@test "process_input_to_file:: fails when input file is empty" {
	local input_file
	local output_file
	input_file=$(mktemp "${BATS_TEST_TMPDIR}/runtime-empty-input.XXXXXX")
	output_file=$(mktemp "${BATS_TEST_TMPDIR}/runtime-empty-output.XXXXXX")
	: >"$input_file"
	SEND_TO_SLACK_CLI_INPUT_FILE="$input_file"

	run process_input_to_file "$output_file"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "input file is empty"
}

@test "process_input_to_file:: reads stdin and sets SEND_TO_SLACK_INPUT_SOURCE" {
	local output_file
	output_file=$(mktemp "${BATS_TEST_TMPDIR}/runtime-stdin-output.XXXXXX")

	if ! process_input_to_file "$output_file" <<<"$(printf '%s\n' \
		'{"from":"stdin"}')"; then
		return 1
	fi
	[[ "$(cat "$output_file")" == '{"from":"stdin"}' ]]
	[[ "$SEND_TO_SLACK_INPUT_SOURCE" == "stdin" ]]
}

@test "init_slack_workspace:: creates and exports a workspace directory" {
	if ! init_slack_workspace; then
		return 1
	fi
	[[ -n "${_SLACK_WORKSPACE}" ]]
	[[ -d "${_SLACK_WORKSPACE}" ]]
	rm -rf "${_SLACK_WORKSPACE}"
}
