#!/usr/bin/env bats
#
# Test file for blocks/image.sh
#

SMOKE_TEST=${SMOKE_TEST:-false}

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		echo "Failed to get git root" >&2
		exit 1
	fi

	SCRIPT="$GIT_ROOT/bin/blocks/image.sh"
	EXAMPLES_FILE="$GIT_ROOT/examples/image.yaml"

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
# create_image
########################################################

@test "create_image:: handles no input" {
	run create_image <<<''
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "input is required"
}

@test "create_image:: handles invalid JSON" {
	run create_image <<<'invalid json'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "input must be valid JSON"
}

@test "create_image:: missing image_url field" {
	local test_input
	test_input='{"alt_text": "Test image"}'
	run create_image <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "image_url field is required"
}

@test "create_image:: missing alt_text field" {
	local test_input
	test_input='{"image_url": "https://example.com/image.png"}'
	run create_image <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "alt_text field is required"
}

@test "create_image:: empty image_url" {
	local test_input
	test_input='{"image_url": "", "alt_text": "Test image"}'
	run create_image <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "image_url field is required"
}

@test "create_image:: empty alt_text" {
	local test_input
	test_input='{"image_url": "https://example.com/image.png", "alt_text": ""}'
	run create_image <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "alt_text field is required"
}

@test "create_image:: alt_text too long" {
	local long_text
	long_text=$(printf 'x%.0s' {1..2001})
	local test_input
	test_input=$(jq -n \
		--arg image_url "https://example.com/image.png" \
		--arg alt_text "$long_text" \
		'{image_url: $image_url, alt_text: $alt_text}')
	run create_image <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "alt_text must be 2000 characters or less"
}

@test "create_image:: title text too long" {
	local long_text
	long_text=$(printf 'x%.0s' {1..2001})
	local test_input
	test_input=$(jq -n \
		--arg image_url "https://example.com/image.png" \
		--arg alt_text "Test image" \
		--arg title_text "$long_text" \
		'{image_url: $image_url, alt_text: $alt_text, title: {type: "plain_text", text: $title_text}}')
	run create_image <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "title text must be 2000 characters or less"
}

@test "create_image:: block_id too long" {
	local long_block_id
	long_block_id=$(printf 'x%.0s' {1..256})
	local test_input
	test_input=$(jq -n \
		--arg image_url "https://example.com/image.png" \
		--arg alt_text "Test image" \
		--arg block_id "$long_block_id" \
		'{image_url: $image_url, alt_text: $alt_text, block_id: $block_id}')
	run create_image <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "block_id must be 255 characters or less"
}

@test "create_image:: invalid title type" {
	local test_input
	test_input='{"image_url": "https://example.com/image.png", "alt_text": "Test image", "title": {"type": "mrkdwn", "text": "Test"}}'
	run create_image <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "title type must be plain_text"
}

@test "create_image:: basic image block" {
	local test_input
	test_input='{"image_url": "https://example.com/image.png", "alt_text": "Test image"}'
	run create_image <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "image"' >/dev/null
	echo "$output" | jq -e '.image_url == "https://example.com/image.png"' >/dev/null
	echo "$output" | jq -e '.alt_text == "Test image"' >/dev/null
}

@test "create_image:: with title" {
	local test_input
	test_input='{"image_url": "https://example.com/image.png", "alt_text": "Test image", "title": {"type": "plain_text", "text": "Image Title"}}'
	run create_image <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.title.type == "plain_text"' >/dev/null
	echo "$output" | jq -e '.title.text == "Image Title"' >/dev/null
}

@test "create_image:: with block_id" {
	local test_input
	test_input='{"image_url": "https://example.com/image.png", "alt_text": "Test image", "block_id": "image_123"}'
	run create_image <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.block_id == "image_123"' >/dev/null
}

@test "create_image:: with all fields" {
	local test_input
	test_input='{"image_url": "https://example.com/image.png", "alt_text": "Test image", "title": {"type": "plain_text", "text": "Image Title"}, "block_id": "image_123"}'
	run create_image <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "image"' >/dev/null
	echo "$output" | jq -e '.image_url' >/dev/null
	echo "$output" | jq -e '.alt_text' >/dev/null
	echo "$output" | jq -e '.title' >/dev/null
	echo "$output" | jq -e '.block_id' >/dev/null
}

@test "create_image:: maximum length alt_text" {
	local max_text
	max_text=$(printf 'x%.0s' {1..2000})
	local test_input
	test_input=$(jq -n \
		--arg image_url "https://example.com/image.png" \
		--arg alt_text "$max_text" \
		'{image_url: $image_url, alt_text: $alt_text}')
	run create_image <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.alt_text | length == 2000' >/dev/null
}

@test "create_image:: from example" {
	local image_json
	image_json=$(yq -o json -r '.jobs[] | select(.name == "basic-image") | .plan[0].params.blocks[0].image' "$EXAMPLES_FILE")

	run create_image <<<"$image_json"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "image"' >/dev/null
	send_request_to_slack "$output"
}

@test "create_image:: with title from example" {
	local image_json
	image_json=$(yq -o json -r '.jobs[] | select(.name == "image-with-title") | .plan[0].params.blocks[0].image' "$EXAMPLES_FILE")

	run create_image <<<"$image_json"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.title' >/dev/null
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

@test "smoke test, image block" {
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "basic-image") | .plan[0].params.blocks' "$EXAMPLES_FILE")

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

@test "smoke test, image-multiple-images" {
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "image-multiple-images") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	if ! parse_payload "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
}
