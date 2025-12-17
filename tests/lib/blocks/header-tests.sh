#!/usr/bin/env bats
#
# Test file for blocks/header.sh
#

SMOKE_TEST=${SMOKE_TEST:-false}

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		echo "Failed to get git root" >&2
		exit 1
	fi

	SCRIPT="$GIT_ROOT/lib/blocks/header.sh"
	EXAMPLES_FILE="$GIT_ROOT/examples/header.yaml"

	if [[ ! -f "$SCRIPT" ]]; then
		echo "Script not found: $SCRIPT" >&2
		exit 1
	fi

	if [[ ! -f "$EXAMPLES_FILE" ]]; then
		echo "Examples file not found: $EXAMPLES_FILE" >&2
		exit 1
	fi

	if [[ -n "$SLACK_BOT_USER_OAUTH_TOKEN" ]]; then
		REAL_TOKEN="$SLACK_BOT_USER_OAUTH_TOKEN"
		export REAL_TOKEN
	fi

	SEND_TO_SLACK_SCRIPT="$GIT_ROOT/send-to-slack.sh"

	export GIT_ROOT
	export SCRIPT
	export EXAMPLES_FILE
	export CHANNEL
	export SEND_TO_SLACK_SCRIPT

	return 0
}

setup() {
	source "$SCRIPT"

	return 0
}

teardown() {
	return 0
}

########################################################
# Helpers
########################################################

send_request_to_slack() {
	[[ "$SMOKE_TEST" != "true" ]] && return 0

	if [[ -z "$REAL_TOKEN" ]]; then
		skip "SLACK_BOT_USER_OAUTH_TOKEN not set"
	fi

	if [[ -z "$CHANNEL" ]]; then
		skip "CHANNEL not set"
	fi

	local input="$1"
	# Create proper Slack message structure with the header block in blocks array
	local message
	message=$(jq -c -n --argjson block "$input" --arg channel "$CHANNEL" '{
		channel: $channel,
		blocks: [$block]
	}')

	local response
	if ! response=$(curl -s -X POST \
		-H "Authorization: Bearer $REAL_TOKEN" \
		-H "Content-Type: application/json; charset=utf-8" \
		-d "$message" \
		"https://slack.com/api/chat.postMessage"); then

		echo "Failed to send request to Slack: curl error" >&2
		return 1
	fi

	if ! echo "$response" | jq -e '.ok' >/dev/null 2>&1; then
		echo "Slack API error: $(echo "$response" | jq -r '.error // "unknown"')" >&2
		return 1
	fi

	return 0
}

########################################################
# create_header
########################################################

@test "create_header:: handles no input" {
	run create_header <<<''
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "input is required"
}

@test "create_header:: handles invalid JSON" {
	run create_header <<<'invalid json'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "input must be valid JSON"
}

@test "create_header:: missing text field" {
	local test_input
	test_input='{"block_id": "test"}'
	run create_header <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "text field is required"
}

@test "create_header:: invalid text type" {
	local test_input
	test_input='{"text": {"type": "mrkdwn", "text": "Test Header"}}'
	run create_header <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "text type must be plain_text"
}

@test "create_header:: missing text content" {
	local test_input
	test_input='{"text": {"type": "plain_text"}}'
	run create_header <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "text.text field is required"
}

@test "create_header:: empty text content" {
	local test_input
	test_input='{"text": {"type": "plain_text", "text": ""}}'
	run create_header <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "text.text field is required"
}

@test "create_header:: text too long" {
	# Generate a string of 151 characters (over the 150 limit)
	local long_text
	long_text=$(printf 'x%.0s' {1..151})
	local test_input
	test_input=$(jq -n --arg text "$long_text" '{text: {type: "plain_text", text: $text}}')
	run create_header <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "header text must be 150 characters or less"
}

@test "create_header:: basic header" {
	local test_input
	test_input='{"text": {"type": "plain_text", "text": "Test Header"}}'
	run create_header <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "header"' >/dev/null
	echo "$output" | jq -e '.text.type == "plain_text"' >/dev/null
	echo "$output" | jq -e '.text.text == "Test Header"' >/dev/null
}

@test "create_header:: with block_id" {
	local test_input
	test_input='{"text": {"type": "plain_text", "text": "Test Header"}, "block_id": "header_123"}'
	run create_header <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.block_id == "header_123"' >/dev/null
}

@test "create_header:: maximum length text" {
	# Generate a string of exactly 150 characters
	local max_text
	max_text=$(printf 'x%.0s' {1..150})
	local test_input
	test_input=$(jq -n --arg text "$max_text" '{text: {type: "plain_text", text: $text}}')
	run create_header <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.text.text | length == 150' >/dev/null
}

@test "create_header:: plain_text only from example" {
	local header_json
	header_json=$(yq -o json -r '.jobs[] | select(.name == "header-with-plain-text-only") | .plan[0].params.blocks[0].header' "$EXAMPLES_FILE")

	run create_header <<<"$header_json"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "header"' >/dev/null
	echo "$output" | jq -e '.text.type == "plain_text"' >/dev/null
	echo "$output" | jq -e '.text.text == "A Heartfelt Header"' >/dev/null
	send_request_to_slack "$output"
}

@test "create_header:: with block_id and maximum text from example" {
	local header_json
	header_json=$(yq -o json -r '.jobs[] | select(.name == "header-with-block-id-and-maximum-text") | .plan[0].params.blocks[0].header' "$EXAMPLES_FILE")

	run create_header <<<"$header_json"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "header"' >/dev/null
	echo "$output" | jq -e '.block_id == "header_with_block_id_001"' >/dev/null
	echo "$output" | jq -e '.text.text | length == 150' >/dev/null
	send_request_to_slack "$output"
}
