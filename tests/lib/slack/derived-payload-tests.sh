#!/usr/bin/env bats
#
# Tests for lib/slack/derived-payload.sh
#

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		fail "Failed to get git root"
	fi

	LIB="$GIT_ROOT/lib/slack/derived-payload.sh"
	if [[ ! -f "$LIB" ]]; then
		fail "Script not found: $LIB"
	fi

	export GIT_ROOT
	export LIB

	return 0
}

setup() {
	source "$LIB"
	_SLACK_WORKSPACE=$(mktemp -d "${BATS_TEST_TMPDIR}/derived-payload.workspace.XXXXXX")
	export _SLACK_WORKSPACE

	return 0
}

teardown() {
	if [[ -n "${_SLACK_WORKSPACE:-}" ]] && [[ -d "${_SLACK_WORKSPACE}" ]]; then
		rm -rf "${_SLACK_WORKSPACE}"
	fi
	return 0
}

@test "_build_derived_input_payload:: fails when _SLACK_WORKSPACE is unset" {
	unset _SLACK_WORKSPACE

	run _build_derived_input_payload '{}' '{"channel":"#c"}' "test"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "_SLACK_WORKSPACE must be a directory"
}

@test "_build_derived_input_payload:: fails when _SLACK_WORKSPACE is not a directory" {
	_SLACK_WORKSPACE="${BATS_TEST_TMPDIR}/derived-payload.not-a-dir"
	export _SLACK_WORKSPACE

	run _build_derived_input_payload '{}' '{"channel":"#c"}' "test"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "_SLACK_WORKSPACE must be a directory"
}

@test "_build_derived_input_payload:: writes Concourse-shaped source and params" {
	local source_json params_json payload_path
	source_json='{"slack_bot_user_oauth_token":"xoxb-test"}'
	params_json='{"channel":"#notifications","blocks":[{"type":"divider"}]}'

	run _build_derived_input_payload "$source_json" "$params_json" "crosspost"
	[[ "$status" -eq 0 ]]
	payload_path="$output"
	[[ -f "$payload_path" ]]
	[[ "$payload_path" == "${_SLACK_WORKSPACE}/crosspost.payload."* ]]

	jq -e '
		.source.slack_bot_user_oauth_token == "xoxb-test"
		and .params.channel == "#notifications"
		and (.params.blocks | length) == 1
		and .params.blocks[0].type == "divider"
	' "$payload_path" >/dev/null
}

@test "_build_derived_input_payload:: removes intermediate source and params temps" {
	local payload_path
	payload_path=$(_build_derived_input_payload '{"a":1}' '{"b":2}' "thread-reply")

	[[ -f "$payload_path" ]]
	# Only the final payload file should remain under the prefix
	local leftover
	leftover=$(find "${_SLACK_WORKSPACE}" -maxdepth 1 \( -name 'thread-reply.source.*' -o -name 'thread-reply.params.*' \) | wc -l)
	[[ "$leftover" -eq 0 ]]
	[[ -f "$payload_path" ]]
}

@test "_build_derived_input_payload:: defaults name_prefix to derived" {
	local payload_path
	payload_path=$(_build_derived_input_payload '{}' '{}')

	[[ -f "$payload_path" ]]
	[[ "$(basename "$payload_path")" == derived.payload.* ]]
}

@test "_build_derived_input_payload:: fails on invalid source JSON" {
	run _build_derived_input_payload 'not-json' '{"channel":"#c"}' "bad"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "jq failed to build payload"
	# No leftover payload from the failed build
	[[ -z "$(find "${_SLACK_WORKSPACE}" -maxdepth 1 -name 'bad.payload.*' 2>/dev/null)" ]]
}

@test "_build_derived_input_payload:: payload file mode is 0600" {
	local payload_path mode
	payload_path=$(_build_derived_input_payload '{}' '{"channel":"#c"}' "mode")
	mode=$(stat -c '%a' "$payload_path" 2>/dev/null || stat -f '%OLp' "$payload_path")
	[[ "$mode" == "600" ]]
}
