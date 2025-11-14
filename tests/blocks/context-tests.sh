#!/usr/bin/env bats
#
# Test file for blocks/context.sh
#

SMOKE_TEST=${SMOKE_TEST:-false}

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		echo "Failed to get git root" >&2
		exit 1
	fi

	SCRIPT="$GIT_ROOT/bin/blocks/context.sh"
	EXAMPLES_FILE="$GIT_ROOT/examples/context.yaml"

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
	# Create proper Slack message structure with the context block in blocks array
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
# create_context
########################################################

@test "create_context:: handles no input" {
	run create_context <<<''
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "input is required"
}

@test "create_context:: handles invalid JSON" {
	run create_context <<<'invalid json'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "input must be valid JSON"
}

@test "create_context:: missing elements field" {
	local input='{"block_id": "test"}'
	run create_context <<<"$input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "elements field is required"
}

@test "create_context:: elements not array" {
	local input='{"elements": "not an array"}'
	run create_context <<<"$input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "elements must be an array"
}

@test "create_context:: empty elements array" {
	local input='{"elements": []}'
	run create_context <<<"$input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "elements array must not be empty"
}

@test "create_context:: basic context with text element" {
	local input='{"elements": [{"type": "plain_text", "text": "Context info"}]}'
	run create_context <<<"$input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "context"' >/dev/null
	echo "$output" | jq -e '.elements[0].type == "plain_text"' >/dev/null
	echo "$output" | jq -e '.elements[0].text == "Context info"' >/dev/null
}

@test "create_context:: context with multiple elements" {
	local input='{"elements": [{"type": "plain_text", "text": "Item 1"}, {"type": "mrkdwn", "text": "*Item 2*"}]}'
	run create_context <<<"$input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "context"' >/dev/null
	echo "$output" | jq -e '.elements | length == 2' >/dev/null
}

@test "create_context:: context with block_id" {
	local input='{"elements": [{"type": "plain_text", "text": "Test"}], "block_id": "context_123"}'
	run create_context <<<"$input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.block_id == "context_123"' >/dev/null
}

@test "create_context:: validates JSON structure" {
	local input='{"elements": [{"type": "plain_text", "text": "Test"}], "block_id": "test_id"}'
	run create_context <<<"$input"
	[[ "$status" -eq 0 ]]

	# Validate the output is proper JSON
	echo "$output" | jq . >/dev/null

	# Validate all expected fields are present
	echo "$output" | jq -e '.type == "context"' >/dev/null
	echo "$output" | jq -e '.elements[0].type == "plain_text"' >/dev/null
	echo "$output" | jq -e '.block_id == "test_id"' >/dev/null
}

@test "create_context:: empty block_id is ignored" {
	local input='{"elements": [{"type": "plain_text", "text": "Test"}], "block_id": ""}'
	run create_context <<<"$input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "context"' >/dev/null

	# block_id should not be present when empty
	run jq -e '.block_id' <<<"$output"
	[[ "$status" -ne 0 ]]
}

@test "create_context:: null block_id is ignored" {
	local input='{"elements": [{"type": "plain_text", "text": "Test"}], "block_id": null}'
	run create_context <<<"$input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "context"' >/dev/null

	# block_id should not be present when null
	run jq -e '.block_id' <<<"$output"
	[[ "$status" -ne 0 ]]
}

@test "create_context:: from example" {
	local context_json
	context_json=$(yq -o json -r '.jobs[] | select(.name == "basic-context") | .plan[0].params.blocks[0].context' "$EXAMPLES_FILE")

	run create_context <<<"$context_json"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "context"' >/dev/null
	send_request_to_slack "$output"
}

@test "create_context:: with block id from example" {
	local context_json
	context_json=$(yq -o json -r '.jobs[] | select(.name == "context-with-block-id") | .plan[0].params.blocks[0].context' "$EXAMPLES_FILE")

	run create_context <<<"$context_json"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.block_id' >/dev/null
	send_request_to_slack "$output"
}

########################################################
# smoke tests
########################################################

smoke_test_setup() {
	local blocks_json="$1"

	if [[ "$SMOKE_TEST" != "true" ]]; then
		skip "SMOKE_TEST is not set"
	fi

	if [[ -z "$REAL_TOKEN" ]]; then
		skip "SLACK_BOT_USER_OAUTH_TOKEN not set"
	fi

	local dry_run="false"
	local channel="notification-testing"

	# Source required scripts
	source "$GIT_ROOT/bin/parse-payload.sh"
	source "$SEND_TO_SLACK_SCRIPT"

	SMOKE_TEST_PAYLOAD_FILE=$(mktemp)
	chmod 0600 "${SMOKE_TEST_PAYLOAD_FILE}"

	jq -n \
		--argjson blocks "$blocks_json" \
		--arg channel "$channel" \
		--arg dry_run "$dry_run" \
		--arg token "$REAL_TOKEN" \
		'{
			source: {
				slack_bot_user_oauth_token: $token
			},
			params: {
				channel: $channel,
				blocks: $blocks,
				dry_run: $dry_run
			}
		}' >"$SMOKE_TEST_PAYLOAD_FILE"

	export SMOKE_TEST_PAYLOAD_FILE
}

smoke_test_teardown() {
	[[ -n "$SMOKE_TEST_PAYLOAD_FILE" ]] && rm -f "$SMOKE_TEST_PAYLOAD_FILE"
	return 0
}

@test "smoke test, context block" {
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "basic-context") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	if ! parse_payload "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi

	if [[ -z "$PAYLOAD" ]]; then
		echo "PAYLOAD is not set" >&2
		return 1
	fi

	run send_notification
	[[ "$status" -eq 0 ]]
}
