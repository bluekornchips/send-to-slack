#!/usr/bin/env bats
#
# Consolidated smoke tests for send-to-slack
#

SMOKE_TEST=${SMOKE_TEST:-false}

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		echo "Failed to get git root" >&2
		exit 1
	fi

	if [[ "$SMOKE_TEST" != "true" ]]; then
		skip "SMOKE_TEST is not set"
	fi

	SEND_TO_SLACK_SCRIPT="$GIT_ROOT/send-to-slack.sh"

	if [[ -n "$SLACK_BOT_USER_OAUTH_TOKEN" ]]; then
		REAL_TOKEN="$SLACK_BOT_USER_OAUTH_TOKEN"
		export REAL_TOKEN
	fi

	export GIT_ROOT
	export SEND_TO_SLACK_SCRIPT
}

setup() {
	SEND_TO_SLACK_ROOT="$GIT_ROOT"
	export SEND_TO_SLACK_ROOT

	source "$GIT_ROOT/bin/parse-payload.sh"
	source "$SEND_TO_SLACK_SCRIPT"
}

teardown() {
	[[ -n "$SMOKE_TEST_PAYLOAD_FILE" ]] && rm -f "$SMOKE_TEST_PAYLOAD_FILE"
	return 0
}

########################################################
# Helpers
########################################################

smoke_test_setup() {
	local blocks_json="$1"

	if [[ -z "$REAL_TOKEN" ]]; then
		skip "SLACK_BOT_USER_OAUTH_TOKEN not set"
	fi

	local dry_run="false"
	local channel="notification-testing"

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

########################################################
# Table block smoke tests
########################################################

@test "smoke test, table basic with raw_text cells" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/table.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "table-basic-with-raw-text-cells") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! parsed_payload=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		return 1
	fi

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke test, table with all features column settings block_id and rich_text" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/table.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "table-with-all-features-column-settings-block-id-and-rich-text") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! parsed_payload=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		return 1
	fi

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

########################################################
# Image block smoke tests
########################################################

@test "smoke test, image block with url title and block_id" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/image.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "image-with-url-title-and-block-id") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! parsed_payload=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		return 1
	fi

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke test, image block with slack_file url" {
	skip "Requires real Slack file URL from actual file upload"

	local EXAMPLES_FILE="$GIT_ROOT/examples/image.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "image-with-slack-file-url") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! parsed_payload=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		return 1
	fi

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke test, image block with slack_file id" {
	skip "Requires real Slack file ID from actual file upload"

	local EXAMPLES_FILE="$GIT_ROOT/examples/image.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "image-with-slack-file-id") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! parsed_payload=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		return 1
	fi

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

########################################################
# Markdown block smoke tests
########################################################

@test "smoke test, markdown block" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/markdown.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "markdown-build-notification") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! parsed_payload=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		return 1
	fi

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

########################################################
# Header block smoke tests
########################################################

@test "smoke test, header block with plain_text only" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/header.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "header-with-plain-text-only") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! parsed_payload=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		return 1
	fi

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke test, header block with block_id and maximum text" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/header.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "header-with-block-id-and-maximum-text") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! parsed_payload=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		return 1
	fi

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

########################################################
# Context block smoke tests
########################################################

@test "smoke test, context block with image and text elements" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/context.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "context-with-image-and-text-elements") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! parsed_payload=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		return 1
	fi

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke test, context block with multiple text elements and block_id" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/context.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "context-with-multiple-text-elements-and-block-id") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! parsed_payload=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		return 1
	fi

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

########################################################
# Section block smoke tests
########################################################

@test "smoke test, section block with mrkdwn text and button accessory" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/section.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "section-with-mrkdwn-text-and-button-accessory") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! parsed_payload=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		return 1
	fi

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke test, section block with fields array and block_id" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/section.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "section-with-fields-array-and-block-id") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! parsed_payload=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		return 1
	fi

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke test, section block with plain_text expand and image accessory" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/section.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "section-with-plain-text-expand-and-image-accessory") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! parsed_payload=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		return 1
	fi

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

########################################################
# Divider block smoke tests
########################################################

@test "smoke test, divider block basic separator" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/divider.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "divider-basic-separator") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! parsed_payload=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		return 1
	fi

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke test, divider block with block_id separating sections" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/divider.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "divider-with-block-id-separating-sections") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! parsed_payload=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		return 1
	fi

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

########################################################
# Video block smoke tests
########################################################

@test "smoke test, video block" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/video.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "basic-video") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! parsed_payload=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		return 1
	fi

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	if [[ "$status" -ne 0 ]]; then
		if echo "$output" | grep -q "Domain is not a valid unfurl domain"; then
			skip "Video domain not configured in Slack app unfurl domains"
		fi
		if echo "$output" | grep -q "video_http_failure"; then
			skip "Video URL not accessible or invalid (Slack API error)"
		fi
		return 1
	fi
	[[ "$status" -eq 0 ]]
}

@test "smoke test, video-with-all-fields" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/video.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "video-with-all-fields") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	if ! parse_payload "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
}

########################################################
# Rich text block smoke tests
########################################################

@test "smoke test, rich-text sends rich-text-section-with-all-elements" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/rich-text.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "rich-text-section-with-all-elements") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! parsed_payload=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		return 1
	fi

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke test, rich-text sends rich-text-attachment-with-color" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/rich-text.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "rich-text-attachment-with-color") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! parsed_payload=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		return 1
	fi

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke test, rich-text sends rich-text-lists-with-all-options" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/rich-text.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "rich-text-lists-with-all-options") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! parsed_payload=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		return 1
	fi

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke test, rich-text sends multiple-rich-text-blocks" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/rich-text.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "multiple-rich-text-blocks") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! parsed_payload=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		return 1
	fi

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke test, rich-text sends rich-text-preformatted-and-quote" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/rich-text.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "rich-text-preformatted-and-quote") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! parsed_payload=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		return 1
	fi

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke test, rich-text sends oversize-rich-text" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/rich-text.yaml"
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
	local parsed_payload
	if ! parsed_payload=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		rm -f "$long_text_file"
		return 1
	fi

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		rm -f "$long_text_file"
		return 1
	fi

	run send_notification "$parsed_payload"
	local test_result=$status

	rm -f "$long_text_file"

	[[ "$test_result" -eq 0 ]]
}

########################################################
# File upload smoke tests
########################################################

@test "smoke test, uploads hello world file" {
	local hello_world_file
	hello_world_file=$(mktemp)
	echo "hello world" >"$hello_world_file"

	local blocks_json
	blocks_json=$(jq -n --arg path "$hello_world_file" '[{ "file": { "path": $path } }]')

	smoke_test_setup "$blocks_json"

	local parsed_payload
	if ! parsed_payload=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		rm -f "$hello_world_file"
		return 1
	fi

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		rm -f "$hello_world_file"
		return 1
	fi

	run send_notification "$parsed_payload"
	local test_result=$status

	rm -f "$hello_world_file"

	[[ "$test_result" -eq 0 ]]
}

@test "smoke test, downloads Slack logo PNG and uploads it" {
	local slack_logo_file
	slack_logo_file=$(mktemp --suffix=".png")

	if ! curl -s -o "$slack_logo_file" "https://docs.slack.dev/img/logos/slack-developers-white.png"; then
		echo "Failed to download Slack logo PNG" >&2
		rm -f "$slack_logo_file"
		return 1
	fi

	if [[ ! -s "$slack_logo_file" ]]; then
		echo "Downloaded Slack logo PNG is empty" >&2
		rm -f "$slack_logo_file"
		return 1
	fi

	local blocks_json
	blocks_json=$(jq -n --arg path "$slack_logo_file" '[{ "file": { "path": $path, "title": "Slack Developers Logo" } }]')

	smoke_test_setup "$blocks_json"

	local parsed_payload
	if ! parsed_payload=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		rm -f "$slack_logo_file"
		return 1
	fi

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		rm -f "$slack_logo_file"
		return 1
	fi

	run send_notification "$parsed_payload"
	local test_result=$status

	rm -f "$slack_logo_file"

	[[ "$test_result" -eq 0 ]]
}

@test "smoke test, multiple file blocks in blocks array" {
	local file1
	local file2
	file1=$(mktemp)
	file2=$(mktemp)
	echo "File 1 content" >"$file1"
	echo "File 2 content" >"$file2"

	local blocks_json
	blocks_json=$(jq -n \
		--arg path1 "$file1" \
		--arg path2 "$file2" \
		'[
			{ "file": { "path": $path1, "title": "First File" } },
			{ "file": { "path": $path2, "title": "Second File" } }
		]')

	smoke_test_setup "$blocks_json"

	local parsed_payload
	if ! parsed_payload=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		rm -f "$file1" "$file2"
		return 1
	fi

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		rm -f "$file1" "$file2"
		return 1
	fi

	run send_notification "$parsed_payload"
	local test_result=$status

	rm -f "$file1" "$file2"

	[[ "$test_result" -eq 0 ]]
}

@test "smoke test, file block without title uses filename" {
	local test_file
	test_file=$(mktemp --suffix=".txt")
	echo "Test content" >"$test_file"

	local blocks_json
	blocks_json=$(jq -n --arg path "$test_file" '[{ "file": { "path": $path } }]')

	smoke_test_setup "$blocks_json"

	local parsed_payload
	if ! parsed_payload=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		rm -f "$test_file"
		return 1
	fi

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		rm -f "$test_file"
		return 1
	fi

	run send_notification "$parsed_payload"
	local test_result=$status

	rm -f "$test_file"

	[[ "$test_result" -eq 0 ]]
}

@test "smoke test, file block mixed with other blocks" {
	local test_file
	test_file=$(mktemp)
	echo "Report content" >"$test_file"

	local blocks_json
	blocks_json=$(jq -n \
		--arg path "$test_file" \
		'[
			{ "header": { "text": { "type": "plain_text", "text": "Report" } } },
			{ "section": { "type": "text", "text": { "type": "mrkdwn", "text": "See attached file" } } },
			{ "file": { "path": $path, "title": "Report File" } },
			{ "context": { "elements": [{ "type": "plain_text", "text": "Generated by CI" }] } }
		]')

	smoke_test_setup "$blocks_json"

	local parsed_payload
	if ! parsed_payload=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		rm -f "$test_file"
		return 1
	fi

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		rm -f "$test_file"
		return 1
	fi

	run send_notification "$parsed_payload"
	local test_result=$status

	rm -f "$test_file"

	[[ "$test_result" -eq 0 ]]
}

@test "smoke test, file permissions debug after upload" {
	local test_file
	test_file=$(mktemp --suffix=".txt")
	echo "Permission test content" >"$test_file"

	chmod 644 "$test_file"

	local initial_perms
	initial_perms=$(stat -c "%a %A" "$test_file" 2>/dev/null || stat -f "%OLp %Sp" "$test_file" 2>/dev/null || echo "unknown")
	echo "Initial file permissions: $initial_perms" >&2

	local blocks_json
	blocks_json=$(jq -n --arg path "$test_file" '[{ "file": { "path": $path, "title": "Permission Test File" } }]')

	smoke_test_setup "$blocks_json"

	local parsed_payload
	if ! parsed_payload=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		rm -f "$test_file"
		return 1
	fi

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		rm -f "$test_file"
		return 1
	fi

	run send_notification "$parsed_payload"
	local test_result=$status

	local final_perms
	final_perms=$(stat -c "%a %A" "$test_file" 2>/dev/null || stat -f "%OLp %Sp" "$test_file" 2>/dev/null || echo "unknown")
	echo "Final file permissions: $final_perms" >&2

	[[ "$initial_perms" == "$final_perms" ]]
	[[ -f "$test_file" ]]
	[[ -r "$test_file" ]]

	local file_content
	file_content=$(cat "$test_file")
	[[ "$file_content" == "Permission test content" ]]

	local file_readable
	local file_size
	file_readable=$([ -r "$test_file" ] && echo "yes" || echo "no")
	file_size=$(stat -c%s "$test_file" 2>/dev/null || stat -f%z "$test_file" 2>/dev/null)
	cat >&2 <<-EOF
		Permission debug summary:
			Initial: $initial_perms
			Final: $final_perms
			File readable: $file_readable
			File size: $file_size bytes
	EOF

	rm -f "$test_file"

	[[ "$test_result" -eq 0 ]]
}

########################################################
# Parse payload smoke tests
########################################################

@test "smoke test, params.raw" {
	local raw_params
	raw_params='{"channel": "notification-testing", "dry_run": "false", "blocks": [{"section": {"type": "text", "text": {"type": "plain_text", "text": "Smoke test for params.raw"}}}] }'

	local params_json
	params_json=$(jq -n --arg raw "$raw_params" '{ raw: $raw }')

	SMOKE_TEST_PAYLOAD_FILE=$(mktemp)
	chmod 0600 "${SMOKE_TEST_PAYLOAD_FILE}"

	jq -n \
		--arg token "$REAL_TOKEN" \
		--argjson params "$params_json" \
		'{
			source: {
				slack_bot_user_oauth_token: $token
			},
			params: $params
		}' >"$SMOKE_TEST_PAYLOAD_FILE"

	local payload_output
	if ! payload_output=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		return 1
	fi

	if [[ -z "$payload_output" ]]; then
		echo "payload output is empty" >&2
		return 1
	fi

	echo "$payload_output" | jq -e '.channel == "notification-testing"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].type == "section"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].text.type == "plain_text"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].text.text == "Smoke test for params.raw"' >/dev/null
}

@test "smoke test, params.from_file" {
	local payload_file
	payload_file=$(mktemp)

	jq -n \
		'{
			channel: "notification-testing",
			dry_run: "false",
			blocks: [{
				section: {
					type: "text",
					text: {
						type: "plain_text",
						text: "Smoke test for params.from_file"
					}
				}
			}]
		}' >"$payload_file"

	local params_json
	params_json=$(jq -n --arg file "$payload_file" '{ from_file: $file }')

	SMOKE_TEST_PAYLOAD_FILE=$(mktemp)
	chmod 0600 "${SMOKE_TEST_PAYLOAD_FILE}"

	jq -n \
		--arg token "$REAL_TOKEN" \
		--argjson params "$params_json" \
		'{
			source: {
				slack_bot_user_oauth_token: $token
			},
			params: $params
		}' >"$SMOKE_TEST_PAYLOAD_FILE"

	local payload_output
	if ! payload_output=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		rm -f "$payload_file"
		return 1
	fi

	if [[ -z "$payload_output" ]]; then
		echo "payload output is empty" >&2
		rm -f "$payload_file"
		return 1
	fi

	echo "$payload_output" | jq -e '.channel == "notification-testing"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].type == "section"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].text.type == "plain_text"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].text.text == "Smoke test for params.from_file"' >/dev/null

	rm -f "$payload_file"
}
