#!/usr/bin/env bats
#
# Test file for blocks/actions.sh
#

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		echo "Failed to get git root" >&2
		exit 1
	fi

	SCRIPT="$GIT_ROOT/lib/blocks/actions.sh"
	EXAMPLES_FILE="$GIT_ROOT/examples/actions.yaml"
	SEND_TO_SLACK_SCRIPT="$GIT_ROOT/send-to-slack.sh"

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

	return 0
}

teardown() {
	return 0
}

########################################################
# create_button_element
########################################################

@test "create_button_element:: handles no input" {
	run create_button_element ""
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "button_json is required"
}

@test "create_button_element:: handles invalid JSON" {
	run create_button_element "invalid json"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "button_json must be valid JSON"
}

@test "create_button_element:: missing text field" {
	local input='{"action_id": "test_action"}'
	run create_button_element "$input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "text is required"
}

@test "create_button_element:: missing text.type" {
	local input='{"text": {"text": "Click me"}, "action_id": "test_action"}'
	run create_button_element "$input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "text.type is required"
}

@test "create_button_element:: missing action_id" {
	local input='{"text": {"type": "plain_text", "text": "Click me"}}'
	run create_button_element "$input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "action_id is required"
}

@test "create_button_element:: basic button with plain_text" {
	local input='{"text": {"type": "plain_text", "text": "Click me"}, "action_id": "test_action"}'
	run create_button_element "$input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "button"' >/dev/null
	echo "$output" | jq -e '.text.type == "plain_text"' >/dev/null
	echo "$output" | jq -e '.text.text == "Click me"' >/dev/null
	echo "$output" | jq -e '.action_id == "test_action"' >/dev/null
}

@test "create_button_element:: button with mrkdwn text" {
	local input='{"text": {"type": "mrkdwn", "text": "*Click me*"}, "action_id": "test_action"}'
	run create_button_element "$input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.text.type == "mrkdwn"' >/dev/null
}

@test "create_button_element:: button with url" {
	local input='{"text": {"type": "plain_text", "text": "Visit"}, "action_id": "test_action", "url": "https://example.com"}'
	run create_button_element "$input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.url == "https://example.com"' >/dev/null
}

@test "create_button_element:: button with value" {
	local input='{"text": {"type": "plain_text", "text": "Click"}, "action_id": "test_action", "value": "clicked"}'
	run create_button_element "$input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.value == "clicked"' >/dev/null
}

@test "create_button_element:: button with style primary" {
	local input='{"text": {"type": "plain_text", "text": "Submit"}, "action_id": "test_action", "style": "primary"}'
	run create_button_element "$input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.style == "primary"' >/dev/null
}

@test "create_button_element:: button with style danger" {
	local input='{"text": {"type": "plain_text", "text": "Delete"}, "action_id": "test_action", "style": "danger"}'
	run create_button_element "$input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.style == "danger"' >/dev/null
}

@test "create_button_element:: button with all optional fields" {
	local input='{"text": {"type": "plain_text", "text": "Full Button"}, "action_id": "test_action", "url": "https://example.com", "value": "full", "style": "primary"}'
	run create_button_element "$input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.url == "https://example.com"' >/dev/null
	echo "$output" | jq -e '.value == "full"' >/dev/null
	echo "$output" | jq -e '.style == "primary"' >/dev/null
}

########################################################
# create_actions
########################################################

@test "create_actions:: handles no input" {
	run create_actions <<<''
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "input is required"
}

@test "create_actions:: handles invalid JSON" {
	run create_actions <<<'invalid json'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "input must be valid JSON"
}

@test "create_actions:: missing elements field" {
	local input='{"block_id": "test"}'
	run create_actions <<<"$input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "elements array is required"
}

@test "create_actions:: empty elements array" {
	local input='{"elements": []}'
	run create_actions <<<"$input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "elements array is required"
}

@test "create_actions:: basic actions block with single button" {
	local input='{"elements": [{"type": "button", "text": {"type": "plain_text", "text": "Click"}, "action_id": "test_action"}]}'
	run create_actions <<<"$input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "actions"' >/dev/null
	echo "$output" | jq -e '.elements | length == 1' >/dev/null
	echo "$output" | jq -e '.elements[0].type == "button"' >/dev/null
}

@test "create_actions:: actions block with multiple buttons" {
	local input='{"elements": [{"type": "button", "text": {"type": "plain_text", "text": "Button 1"}, "action_id": "action1"}, {"type": "button", "text": {"type": "plain_text", "text": "Button 2"}, "action_id": "action2"}]}'
	run create_actions <<<"$input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.elements | length == 2' >/dev/null
	echo "$output" | jq -e '.elements[0].action_id == "action1"' >/dev/null
	echo "$output" | jq -e '.elements[1].action_id == "action2"' >/dev/null
}

@test "create_actions:: actions block with block_id" {
	local input='{"elements": [{"type": "button", "text": {"type": "plain_text", "text": "Click"}, "action_id": "test_action"}], "block_id": "actions_123"}'
	run create_actions <<<"$input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.block_id == "actions_123"' >/dev/null
}

@test "create_actions:: unsupported element type" {
	local input='{"elements": [{"type": "datepicker", "action_id": "test"}]}'
	run create_actions <<<"$input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "unsupported element type"
}

@test "create_actions:: too many elements" {
	local elements="["
	for i in {1..26}; do
		if [[ $i -gt 1 ]]; then
			elements+=","
		fi
		elements+="{\"type\": \"button\", \"text\": {\"type\": \"plain_text\", \"text\": \"Button $i\"}, \"action_id\": \"action$i\"}"
	done
	elements+="]"
	local input="{\"elements\": $elements}"
	run create_actions <<<"$input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "elements array cannot exceed 25 elements"
}

@test "create_actions:: from example channel button" {
	local actions_json
	actions_json=$(yq -o json -r '.jobs[] | select(.name == "actions-button-channel") | .plan[0].params.blocks[1].actions' "$EXAMPLES_FILE")

	run create_actions <<<"$actions_json"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "actions"' >/dev/null
	echo "$output" | jq -e '.elements[0].action_id == "send_channel_message"' >/dev/null
}

@test "create_actions:: from example user button" {
	local actions_json
	actions_json=$(yq -o json -r '.jobs[] | select(.name == "actions-button-user") | .plan[0].params.blocks[1].actions' "$EXAMPLES_FILE")

	run create_actions <<<"$actions_json"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "actions"' >/dev/null
	echo "$output" | jq -e '.elements[0].action_id == "send_user_message"' >/dev/null
}
