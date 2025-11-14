#!/usr/bin/env bats
#
# Test file for blocks/video.sh
#

SMOKE_TEST=${SMOKE_TEST:-false}

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		echo "Failed to get git root" >&2
		exit 1
	fi

	SCRIPT="$GIT_ROOT/bin/blocks/video.sh"
	EXAMPLES_FILE="$GIT_ROOT/examples/video.yaml"

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
		local error
		error=$(echo "$response" | jq -r '.error // "unknown"')
		local error_msg
		error_msg=$(echo "$response" | jq -r '.errors[]? // empty' | head -1)

		if echo "$error_msg" | grep -q "Domain is not a valid unfurl domain"; then
			echo "Skipping test: Video domain not configured in Slack app unfurl domains" >&2
			return 0
		fi

		echo "Slack API error: $error" >&2
		if [[ -n "$error_msg" ]]; then
			echo "Error details: $error_msg" >&2
		fi
		return 1
	fi

	return 0
}

########################################################
# create_video
########################################################

@test "create_video:: handles no input" {
	run create_video <<<''
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "input is required"
}

@test "create_video:: handles invalid JSON" {
	run create_video <<<'invalid json'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "input must be valid JSON"
}

@test "create_video:: missing video_url field" {
	local test_input
	test_input='{"thumbnail_url": "https://example.com/thumb.jpg", "alt_text": "Test video", "title": {"type": "plain_text", "text": "Video"}}'
	run create_video <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "video_url field is required"
}

@test "create_video:: missing thumbnail_url field" {
	local test_input
	test_input='{"video_url": "https://example.com/video.mp4", "alt_text": "Test video", "title": {"type": "plain_text", "text": "Video"}}'
	run create_video <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "thumbnail_url field is required"
}

@test "create_video:: missing alt_text field" {
	local test_input
	test_input='{"video_url": "https://example.com/video.mp4", "thumbnail_url": "https://example.com/thumb.jpg", "title": {"type": "plain_text", "text": "Video"}}'
	run create_video <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "alt_text field is required"
}

@test "create_video:: missing title field" {
	local test_input
	test_input='{"video_url": "https://example.com/video.mp4", "thumbnail_url": "https://example.com/thumb.jpg", "alt_text": "Test video"}'
	run create_video <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "title field is required"
}

@test "create_video:: empty video_url" {
	local test_input
	test_input='{"video_url": "", "thumbnail_url": "https://example.com/thumb.jpg", "alt_text": "Test video", "title": {"type": "plain_text", "text": "Video"}}'
	run create_video <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "video_url field is required"
}

@test "create_video:: empty thumbnail_url" {
	local test_input
	test_input='{"video_url": "https://example.com/video.mp4", "thumbnail_url": "", "alt_text": "Test video", "title": {"type": "plain_text", "text": "Video"}}'
	run create_video <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "thumbnail_url field is required"
}

@test "create_video:: empty alt_text" {
	local test_input
	test_input='{"video_url": "https://example.com/video.mp4", "thumbnail_url": "https://example.com/thumb.jpg", "alt_text": "", "title": {"type": "plain_text", "text": "Video"}}'
	run create_video <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "alt_text field is required"
}

@test "create_video:: alt_text too long" {
	local long_text
	long_text=$(printf 'x%.0s' {1..2001})
	local test_input
	test_input=$(jq -n \
		--arg video_url "https://example.com/video.mp4" \
		--arg thumbnail_url "https://example.com/thumb.jpg" \
		--arg alt_text "$long_text" \
		--argjson title '{"type": "plain_text", "text": "Video"}' \
		'{video_url: $video_url, thumbnail_url: $thumbnail_url, alt_text: $alt_text, title: $title}')
	run create_video <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "alt_text must be 2000 characters or less"
}

@test "create_video:: title text too long" {
	local long_text
	long_text=$(printf 'x%.0s' {1..2001})
	local test_input
	test_input=$(jq -n \
		--arg video_url "https://example.com/video.mp4" \
		--arg thumbnail_url "https://example.com/thumb.jpg" \
		--arg alt_text "Test video" \
		--arg title_text "$long_text" \
		'{video_url: $video_url, thumbnail_url: $thumbnail_url, alt_text: $alt_text, title: {type: "plain_text", text: $title_text}}')
	run create_video <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "title text must be 2000 characters or less"
}

@test "create_video:: description text too long" {
	local long_text
	long_text=$(printf 'x%.0s' {1..2001})
	local test_input
	test_input=$(jq -n \
		--arg video_url "https://example.com/video.mp4" \
		--arg thumbnail_url "https://example.com/thumb.jpg" \
		--arg alt_text "Test video" \
		--argjson title '{"type": "plain_text", "text": "Video"}' \
		--arg desc_text "$long_text" \
		'{video_url: $video_url, thumbnail_url: $thumbnail_url, alt_text: $alt_text, title: $title, description: {type: "plain_text", text: $desc_text}}')
	run create_video <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "description text must be 2000 characters or less"
}

@test "create_video:: author_name too long" {
	local long_text
	long_text=$(printf 'x%.0s' {1..2001})
	local test_input
	test_input=$(jq -n \
		--arg video_url "https://example.com/video.mp4" \
		--arg thumbnail_url "https://example.com/thumb.jpg" \
		--arg alt_text "Test video" \
		--argjson title '{"type": "plain_text", "text": "Video"}' \
		--arg author_name "$long_text" \
		'{video_url: $video_url, thumbnail_url: $thumbnail_url, alt_text: $alt_text, title: $title, author_name: $author_name}')
	run create_video <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "author_name must be 2000 characters or less"
}

@test "create_video:: provider_name too long" {
	local long_text
	long_text=$(printf 'x%.0s' {1..2001})
	local test_input
	test_input=$(jq -n \
		--arg video_url "https://example.com/video.mp4" \
		--arg thumbnail_url "https://example.com/thumb.jpg" \
		--arg alt_text "Test video" \
		--argjson title '{"type": "plain_text", "text": "Video"}' \
		--arg provider_name "$long_text" \
		'{video_url: $video_url, thumbnail_url: $thumbnail_url, alt_text: $alt_text, title: $title, provider_name: $provider_name}')
	run create_video <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "provider_name must be 2000 characters or less"
}

@test "create_video:: block_id too long" {
	local long_block_id
	long_block_id=$(printf 'x%.0s' {1..256})
	local test_input
	test_input=$(jq -n \
		--arg video_url "https://example.com/video.mp4" \
		--arg thumbnail_url "https://example.com/thumb.jpg" \
		--arg alt_text "Test video" \
		--argjson title '{"type": "plain_text", "text": "Video"}' \
		--arg block_id "$long_block_id" \
		'{video_url: $video_url, thumbnail_url: $thumbnail_url, alt_text: $alt_text, title: $title, block_id: $block_id}')
	run create_video <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "block_id must be 255 characters or less"
}

@test "create_video:: invalid title type" {
	local test_input
	test_input='{"video_url": "https://example.com/video.mp4", "thumbnail_url": "https://example.com/thumb.jpg", "alt_text": "Test video", "title": {"type": "mrkdwn", "text": "Video"}}'
	run create_video <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "title type must be plain_text"
}

@test "create_video:: invalid description type" {
	local test_input
	test_input='{"video_url": "https://example.com/video.mp4", "thumbnail_url": "https://example.com/thumb.jpg", "alt_text": "Test video", "title": {"type": "plain_text", "text": "Video"}, "description": {"type": "mrkdwn", "text": "Description"}}'
	run create_video <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "description type must be plain_text"
}

@test "create_video:: basic video block" {
	local test_input
	test_input='{"video_url": "https://example.com/video.mp4", "thumbnail_url": "https://example.com/thumb.jpg", "alt_text": "Test video", "title": {"type": "plain_text", "text": "Video Title"}}'
	run create_video <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "video"' >/dev/null
	echo "$output" | jq -e '.video_url == "https://example.com/video.mp4"' >/dev/null
	echo "$output" | jq -e '.thumbnail_url == "https://example.com/thumb.jpg"' >/dev/null
	echo "$output" | jq -e '.alt_text == "Test video"' >/dev/null
	echo "$output" | jq -e '.title.text == "Video Title"' >/dev/null
}

@test "create_video:: with description" {
	local test_input
	test_input='{"video_url": "https://example.com/video.mp4", "thumbnail_url": "https://example.com/thumb.jpg", "alt_text": "Test video", "title": {"type": "plain_text", "text": "Video Title"}, "description": {"type": "plain_text", "text": "Video description"}}'
	run create_video <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.description.type == "plain_text"' >/dev/null
	echo "$output" | jq -e '.description.text == "Video description"' >/dev/null
}

@test "create_video:: with provider info" {
	local test_input
	test_input='{"video_url": "https://example.com/video.mp4", "thumbnail_url": "https://example.com/thumb.jpg", "alt_text": "Test video", "title": {"type": "plain_text", "text": "Video Title"}, "provider_name": "YouTube", "provider_icon_url": "https://example.com/icon.png"}'
	run create_video <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.provider_name == "YouTube"' >/dev/null
	echo "$output" | jq -e '.provider_icon_url == "https://example.com/icon.png"' >/dev/null
}

@test "create_video:: with author info" {
	local test_input
	test_input='{"video_url": "https://example.com/video.mp4", "thumbnail_url": "https://example.com/thumb.jpg", "alt_text": "Test video", "title": {"type": "plain_text", "text": "Video Title"}, "author_name": "John Doe"}'
	run create_video <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.author_name == "John Doe"' >/dev/null
}

@test "create_video:: with title_url" {
	local test_input
	test_input='{"video_url": "https://example.com/video.mp4", "thumbnail_url": "https://example.com/thumb.jpg", "alt_text": "Test video", "title": {"type": "plain_text", "text": "Video Title"}, "title_url": "https://example.com/video"}'
	run create_video <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.title_url == "https://example.com/video"' >/dev/null
}

@test "create_video:: with block_id" {
	local test_input
	test_input='{"video_url": "https://example.com/video.mp4", "thumbnail_url": "https://example.com/thumb.jpg", "alt_text": "Test video", "title": {"type": "plain_text", "text": "Video Title"}, "block_id": "video_123"}'
	run create_video <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.block_id == "video_123"' >/dev/null
}

@test "create_video:: with all fields" {
	local test_input
	test_input='{"video_url": "https://example.com/video.mp4", "thumbnail_url": "https://example.com/thumb.jpg", "alt_text": "Test video", "title": {"type": "plain_text", "text": "Video Title"}, "title_url": "https://example.com/video", "description": {"type": "plain_text", "text": "Description"}, "author_name": "John Doe", "provider_name": "YouTube", "provider_icon_url": "https://example.com/icon.png", "block_id": "video_123"}'
	run create_video <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "video"' >/dev/null
	echo "$output" | jq -e '.video_url' >/dev/null
	echo "$output" | jq -e '.thumbnail_url' >/dev/null
	echo "$output" | jq -e '.alt_text' >/dev/null
	echo "$output" | jq -e '.title' >/dev/null
	echo "$output" | jq -e '.title_url' >/dev/null
	echo "$output" | jq -e '.description' >/dev/null
	echo "$output" | jq -e '.author_name' >/dev/null
	echo "$output" | jq -e '.provider_name' >/dev/null
	echo "$output" | jq -e '.provider_icon_url' >/dev/null
	echo "$output" | jq -e '.block_id' >/dev/null
}

@test "create_video:: from example" {
	local video_json
	video_json=$(yq -o json -r '.jobs[] | select(.name == "basic-video") | .plan[0].params.blocks[0].video' "$EXAMPLES_FILE")

	run create_video <<<"$video_json"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "video"' >/dev/null
	send_request_to_slack "$output"
}

@test "create_video:: with description from example" {
	local video_json
	video_json=$(yq -o json -r '.jobs[] | select(.name == "video-with-description") | .plan[0].params.blocks[0].video' "$EXAMPLES_FILE")

	run create_video <<<"$video_json"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.description' >/dev/null
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

@test "smoke test, video block" {
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "basic-video") | .plan[0].params.blocks' "$EXAMPLES_FILE")

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
	if [[ "$status" -ne 0 ]]; then
		if echo "$output" | grep -q "Domain is not a valid unfurl domain"; then
			skip "Video domain not configured in Slack app unfurl domains"
		fi
		return 1
	fi
	[[ "$status" -eq 0 ]]
}

@test "smoke test, video-with-all-fields" {
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "video-with-all-fields") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	if ! parse_payload "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
}
