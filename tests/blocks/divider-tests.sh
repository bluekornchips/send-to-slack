#!/usr/bin/env bats
#
# Test file for blocks/divider.sh
#

SMOKE_TEST=${SMOKE_TEST:-false}

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		echo "Failed to get git root" >&2
		exit 1
	fi

	SCRIPT="$GIT_ROOT/bin/blocks/divider.sh"
	EXAMPLES_FILE="$GIT_ROOT/examples/divider.yaml"

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
	export SEND_TO_SLACK_SCRIPT

	return 0
}

setup() {
	source "$SCRIPT"

	SEND_TO_SLACK_ROOT="$GIT_ROOT"
	export SEND_TO_SLACK_ROOT

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

	local input="$1"
	# Create proper Slack message structure with the divider block in blocks array
	local message
	message=$(jq -c -n --argjson block "$input" '{
		channel: "notification-testing",
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
# create_divider
########################################################

@test "create_divider:: basic divider block" {
	run create_divider <<<''
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "divider"' >/dev/null
}

@test "create_divider:: divider with empty JSON" {
	run create_divider <<<'{}'
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "divider"' >/dev/null
}

@test "create_divider:: divider with block_id" {
	local input='{"block_id": "divider_123"}'
	run create_divider <<<"$input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "divider"' >/dev/null
	echo "$output" | jq -e '.block_id == "divider_123"' >/dev/null
}

@test "create_divider:: handles invalid JSON" {
	run create_divider <<<'invalid json'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "input must be valid JSON"
}

@test "create_divider:: validates JSON structure" {
	local input='{"block_id": "test"}'
	run create_divider <<<"$input"
	[[ "$status" -eq 0 ]]

	# Validate the output is proper JSON
	echo "$output" | jq . >/dev/null

	# Validate required fields are present
	echo "$output" | jq -e '.type == "divider"' >/dev/null
	echo "$output" | jq -e '.block_id == "test"' >/dev/null
}

@test "create_divider:: empty block_id is ignored" {
	local input='{"block_id": ""}'
	run create_divider <<<"$input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "divider"' >/dev/null

	# block_id should not be present when empty
	run jq -e '.block_id' <<<"$output"
	[[ "$status" -ne 0 ]]
}

@test "create_divider:: null block_id is ignored" {
	local input='{"block_id": null}'
	run create_divider <<<"$input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "divider"' >/dev/null

	# block_id should not be present when null
	run jq -e '.block_id' <<<"$output"
	[[ "$status" -ne 0 ]]
}

@test "create_divider:: from example" {
	local divider_json
	divider_json=$(yq -o json -r '.jobs[] | select(.name == "basic-divider") | .plan[0].params.blocks[0].divider' "$EXAMPLES_FILE")

	run create_divider <<<"$divider_json"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "divider"' >/dev/null
	send_request_to_slack "$output"
}

@test "create_divider:: with block id from example" {
	local divider_json
	divider_json=$(yq -o json -r '.jobs[] | select(.name == "divider-with-block-id") | .plan[0].params.blocks[0].divider' "$EXAMPLES_FILE")

	run create_divider <<<"$divider_json"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.block_id' >/dev/null
	send_request_to_slack "$output"
}
