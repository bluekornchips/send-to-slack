#!/usr/bin/env bats
#
# Test file for blocks/rich_text.sh
#

SMOKE_TEST=${SMOKE_TEST:-false}

setup_file() {

	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		echo "Failed to get git root" >&2
		exit 1
	fi

	SCRIPT="$GIT_ROOT/bin/blocks/rich-text.sh"
	EXAMPLES_FILE="$GIT_ROOT/examples/rich-text.yaml"
	SEND_TO_SLACK_SCRIPT="$GIT_ROOT/send-to-slack.sh"

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

	export GIT_ROOT
	export SCRIPT
	export EXAMPLES_FILE
	export SEND_TO_SLACK_SCRIPT

}

setup() {
	source "$SCRIPT"

	SEND_TO_SLACK_ROOT="$GIT_ROOT"

	export SEND_TO_SLACK_ROOT

	return 0
}

########################################################
# create_rich_text
########################################################
@test "create_rich_text:: handles no input" {
	run create_rich_text <<<''

	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "input is required"
}

@test "create_rich_text:: handles invalid JSON" {
	run create_rich_text <<<'invalid json'

	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "input must be valid JSON"
}

@test "create_rich_text:: missing elements" {
	run create_rich_text <<<'{"block_id": "test_id"}'

	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "elements field is required"
}

@test "create_rich_text:: with block_id" {
	run create_rich_text <<<'{"block_id": "test_id", "elements": [{"type": "text", "text": "Hello, world!"}]}'

	[[ "$status" -eq 0 ]]
	echo "$output" | jq '.block_id == "test_id"' >/dev/null
}

@test "create_rich_text:: with elements" {
	run create_rich_text <<<'{"elements": [{"type": "text", "text": "Hello, world!"}]}'

	[[ "$status" -eq 0 ]]
	echo "$output" | jq '.elements[0].text == "Hello, world!"' >/dev/null
}

@test "create_rich_text:: text over 4000 characters uploads as file" {
	# Generate a string of 4001 characters
	local text
	text=$(printf 'x%.0s' {1..4001})
	local block_value
	block_value=$(jq -n --arg text "$text" '{type: "rich_text", elements: [{"type": "text", "text": $text}]}')

	# Mock the file upload script to avoid actual API calls
	local mock_script="/tmp/mock_file_upload.sh"
	cat >"$mock_script" <<'EOF'
#!/bin/bash
echo '{"type": "section", "text": {"type": "mrkdwn", "text": "<http://example.com/file.txt|oversized-rich-text.txt>"}}'
EOF
	chmod +x "$mock_script"

	# Override the file upload script path
	local original_upload_script="$UPLOAD_FILE_SCRIPT"
	UPLOAD_FILE_SCRIPT="$mock_script"

	run create_rich_text <<<"$block_value"

	# Restore original
	UPLOAD_FILE_SCRIPT="$original_upload_script"
	rm -f "$mock_script"

	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "section"' >/dev/null
	echo "$output" | jq -e '.text.type == "mrkdwn"' >/dev/null
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

	source "$GIT_ROOT/bin/parse-payload.sh"
	source "$SEND_TO_SLACK_SCRIPT"

	SMOKE_TEST_PAYLOAD_FILE=$(mktemp)

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

teardown() {
	[[ -n "$SMOKE_TEST_PAYLOAD_FILE" ]] && rm -f "$SMOKE_TEST_PAYLOAD_FILE"
	return 0
}

@test "smoke test, sends basic" {
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "basic") | .plan[0].params.blocks' "$EXAMPLES_FILE")

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

@test "smoke test, sends basic-attachment" {
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "basic-attachment") | .plan[0].params.blocks' "$EXAMPLES_FILE")

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

@test "smoke test, sends two-rich-text-blocks" {
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "two-rich-text-blocks") | .plan[0].params.blocks' "$EXAMPLES_FILE")

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

@test "smoke test, sends rich-text-block-and-attachment" {
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "rich-text-block-and-attachment") | .plan[0].params.blocks' "$EXAMPLES_FILE")

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

@test "smoke test, sends oversize-rich-text" {
	# Generate a string longer than 4000 characters to trigger file upload
	local line_text="This is some test content that will exceed the 4000 character limit for rich text blocks."
	local long_text_file
	long_text_file=$(mktemp -t "oversize-rich-text-XXXXXX.txt")
	for i in {1..450}; do
		echo "$i: $line_text" >>"$long_text_file"
	done

	local long_text
	long_text=$(cat "$long_text_file")

	local blocks_json
	blocks_json=$(jq -n --arg text "$long_text" '[{"rich-text": {"elements": [{"type": "rich_text_section", "elements": [{"type": "text", "text": $text}]}]}}]')

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
