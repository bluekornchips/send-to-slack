#!/usr/bin/env bats
#
# Test file for blocks/context.sh
#

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

	export GIT_ROOT
	export SCRIPT
	export EXAMPLES_FILE

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

@test "create_context:: with image and text elements from example" {
	local context_json
	context_json=$(yq -o json -r '.jobs[] | select(.name == "context-with-image-and-text-elements") | .plan[0].params.blocks[0].context' "$EXAMPLES_FILE")

	run create_context <<<"$context_json"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "context"' >/dev/null
	echo "$output" | jq -e '.elements | length == 2' >/dev/null
	echo "$output" | jq -e '.elements[0].type == "image"' >/dev/null
	echo "$output" | jq -e '.elements[1].type == "mrkdwn"' >/dev/null
}

@test "create_context:: with multiple text elements and block_id from example" {
	local context_json
	context_json=$(yq -o json -r '.jobs[] | select(.name == "context-with-multiple-text-elements-and-block-id") | .plan[0].params.blocks[1].context' "$EXAMPLES_FILE")

	run create_context <<<"$context_json"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "context"' >/dev/null
	echo "$output" | jq -e '.elements | length == 4' >/dev/null
	echo "$output" | jq -e '.block_id == "deployment_context_001"' >/dev/null
}
