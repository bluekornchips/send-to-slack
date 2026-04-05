#!/usr/bin/env bats
#
# Consolidated smoke tests for send-to-slack
#

RUN_SMOKE_TEST=${RUN_SMOKE_TEST:-false}

setup_file() {
	[[ "$RUN_SMOKE_TEST" != "true" ]] && skip "RUN_SMOKE_TEST is not set"

	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		skip "Failed to get git root"
	fi

	if [[ -z "$CHANNEL" ]]; then
		fail "CHANNEL environment variable is not set"
	fi

	export CHANNEL

	SEND_TO_SLACK_SCRIPT="$GIT_ROOT/bin/send-to-slack.sh"

	if [[ -n "$SLACK_BOT_USER_OAUTH_TOKEN" ]]; then
		REAL_TOKEN="$SLACK_BOT_USER_OAUTH_TOKEN"
		export REAL_TOKEN
	fi

	if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
		REAL_WEBHOOK_URL="$SLACK_WEBHOOK_URL"
		export REAL_WEBHOOK_URL
	fi

	export GIT_ROOT
	export CHANNEL
	export SEND_TO_SLACK_SCRIPT
}

setup() {
	source "$GIT_ROOT/lib/slack-api.sh"
	source "$GIT_ROOT/lib/metadata.sh"
	source "$GIT_ROOT/lib/parse/payload.sh"
	source "$SEND_TO_SLACK_SCRIPT"

	_SLACK_WORKSPACE=$(mktemp -d "${BATS_TEST_TMPDIR}/smoke-tests.workspace.XXXXXX")
	export _SLACK_WORKSPACE
}

teardown() {
	rm -rf "$_SLACK_WORKSPACE"
	rm -f "$SMOKE_TEST_PAYLOAD_FILE"
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
	local channel="$CHANNEL"

	SMOKE_TEST_PAYLOAD_FILE=$(mktemp "${BATS_TEST_TMPDIR}/smoke-tests.smoke-payload.XXXXXX")

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

smoke_test_setup_webhook() {
	local blocks_json="$1"

	if [[ -z "${REAL_WEBHOOK_URL:-}" ]]; then
		skip "SLACK_WEBHOOK_URL not set"
	fi

	local dry_run="false"

	SMOKE_TEST_PAYLOAD_FILE=$(mktemp "${BATS_TEST_TMPDIR}/smoke-tests.smoke-payload-webhook.XXXXXX")

	jq -n \
		--argjson blocks "$blocks_json" \
		--arg dry_run "$dry_run" \
		--arg url "$REAL_WEBHOOK_URL" \
		'{
			source: {
				webhook_url: $url
			},
			params: {
				blocks: $blocks,
				dry_run: $dry_run
			}
		}' >"$SMOKE_TEST_PAYLOAD_FILE"

	export SMOKE_TEST_PAYLOAD_FILE
}

smoke_test_setup_ephemeral() {
	local blocks_json="$1"

	if [[ -z "$REAL_TOKEN" ]]; then
		skip "SLACK_BOT_USER_OAUTH_TOKEN not set"
	fi

	if [[ -z "${EPHEMERAL_USER:-}" ]]; then
		skip "EPHEMERAL_USER not set"
	fi

	local dry_run="false"
	local channel="$CHANNEL"
	local ephemeral_user="$EPHEMERAL_USER"

	SMOKE_TEST_PAYLOAD_FILE=$(mktemp "${BATS_TEST_TMPDIR}/smoke-tests.smoke-payload-ephemeral.XXXXXX")

	jq -n \
		--argjson blocks "$blocks_json" \
		--arg channel "$channel" \
		--arg dry_run "$dry_run" \
		--arg token "$REAL_TOKEN" \
		--arg ephemeral_user "$ephemeral_user" \
		'{
			source: {
				slack_bot_user_oauth_token: $token
			},
			params: {
				channel: $channel,
				ephemeral_user: $ephemeral_user,
				blocks: $blocks,
				dry_run: $dry_run
			}
		}' >"$SMOKE_TEST_PAYLOAD_FILE"

	export SMOKE_TEST_PAYLOAD_FILE
}

smoke_test_setup_bot_identity() {
	local blocks_json="$1"
	local username="$2"
	local icon_emoji="$3"

	if [[ -z "$REAL_TOKEN" ]]; then
		skip "SLACK_BOT_USER_OAUTH_TOKEN not set"
	fi

	local dry_run="false"
	local channel="$CHANNEL"

	SMOKE_TEST_PAYLOAD_FILE=$(mktemp "${BATS_TEST_TMPDIR}/smoke-tests.smoke-payload-bot-identity.XXXXXX")

	jq -n \
		--argjson blocks "$blocks_json" \
		--arg channel "$channel" \
		--arg dry_run "$dry_run" \
		--arg token "$REAL_TOKEN" \
		--arg username "$username" \
		--arg icon_emoji "$icon_emoji" \
		'{
			source: {
				slack_bot_user_oauth_token: $token
			},
			params: {
				channel: $channel,
				username: $username,
				icon_emoji: $icon_emoji,
				blocks: $blocks,
				dry_run: $dry_run
			}
		}' >"$SMOKE_TEST_PAYLOAD_FILE"

	export SMOKE_TEST_PAYLOAD_FILE
}

smoke_test_setup_bot_identity_icon_url() {
	local blocks_json="$1"
	local username="$2"
	local icon_url="$3"

	if [[ -z "$REAL_TOKEN" ]]; then
		skip "SLACK_BOT_USER_OAUTH_TOKEN not set"
	fi

	local dry_run="false"
	local channel="$CHANNEL"

	SMOKE_TEST_PAYLOAD_FILE=$(mktemp "${BATS_TEST_TMPDIR}/smoke-tests.smoke-payload-bot-icon-url.XXXXXX")

	jq -n \
		--argjson blocks "$blocks_json" \
		--arg channel "$channel" \
		--arg dry_run "$dry_run" \
		--arg token "$REAL_TOKEN" \
		--arg username "$username" \
		--arg icon_url "$icon_url" \
		'{
			source: {
				slack_bot_user_oauth_token: $token
			},
			params: {
				channel: $channel,
				username: $username,
				icon_url: $icon_url,
				blocks: $blocks,
				dry_run: $dry_run
			}
		}' >"$SMOKE_TEST_PAYLOAD_FILE"

	export SMOKE_TEST_PAYLOAD_FILE
}

# parse_payload must run in this shell, not in command substitution, so exports from
# load_configuration stay set for send_notification. Sets SMOKE_PARSED_PAYLOAD on success.
smoke_parse_payload_capture() {
	local out_file
	local payload_path="$1"

	out_file=$(mktemp "${BATS_TEST_TMPDIR}/smoke-tests.parsed-payload.XXXXXX")
	if ! parse_payload "$payload_path" >"$out_file"; then
		rm -f "$out_file"
		return 1
	fi
	SMOKE_PARSED_PAYLOAD=$(cat "$out_file")
	rm -f "$out_file"
	return 0
}

########################################################
# Table block smoke tests
########################################################

@test "smoke_test:: table basic with raw_text cells" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/table.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "table-basic-with-raw-text-cells") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke_test:: table with all features column settings block_id and rich_text" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/table.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "table-with-all-features-column-settings-block-id-and-rich-text") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke_test:: accepts 100x20 table without hitting ARG_MAX" {
	source "$GIT_ROOT/lib/block-kit/blocks/table.sh"

	local table_output_file
	table_output_file=$(mktemp "$_SLACK_WORKSPACE/table-argmax.XXXXXX")
	TABLE_BLOCK_OUTPUT_FILE="$table_output_file"
	export TABLE_BLOCK_OUTPUT_FILE

	jq -n '[range(100) as $r | [range(20) as $c | {type: "raw_text", text: "r\($r)c\($c)"}]] | {rows: .}' |
		run create_table
	[[ "$status" -eq 0 ]]

	local table_output
	table_output=$(cat "$table_output_file")

	# 100x20 with short cell text totals ~12,000 chars, exceeding the 10,000 limit,
	# so the overflow path is expected: output is an array with a context and file block.
	echo "$table_output" | jq -e 'type == "array"' >/dev/null
	echo "$table_output" | jq -e '.[0].type == "context"' >/dev/null
	echo "$table_output" | jq -e '.[1].file.path | test(".json$")' >/dev/null
}

@test "smoke_test:: 50x20 table overflow falls back to file attachment" {
	if [[ -z "$REAL_TOKEN" ]]; then
		skip "SLACK_BOT_USER_OAUTH_TOKEN not set"
	fi

	local rows_file
	rows_file=$(mktemp "$_SLACK_WORKSPACE/smoke-overflow-rows.XXXXXX")
	jq -n '[range(50) as $r | [range(20) as $c | {type: "raw_text", text: ("r\($r)c\($c)-" + ("x" * (10 + (($r * 20 + $c) % 91))))}]]' \
		>"$rows_file"

	SMOKE_TEST_PAYLOAD_FILE=$(mktemp "${BATS_TEST_TMPDIR}/smoke-tests.smoke-payload.XXXXXX")
	jq -n \
		--slurpfile rows "$rows_file" \
		--arg channel "$CHANNEL" \
		--arg token "$REAL_TOKEN" \
		'{
			source: { slack_bot_user_oauth_token: $token },
			params: {
				channel: $channel,
				dry_run: "false",
				blocks: [{ table: { rows: $rows[0] } }]
			}
		}' >"$SMOKE_TEST_PAYLOAD_FILE"
	export SMOKE_TEST_PAYLOAD_FILE

	local parsed_payload
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke_test:: 100x20 table overflow falls back to file attachment" {
	if [[ -z "$REAL_TOKEN" ]]; then
		skip "SLACK_BOT_USER_OAUTH_TOKEN not set"
	fi

	local rows_file
	rows_file=$(mktemp "$_SLACK_WORKSPACE/smoke-overflow-rows.XXXXXX")
	jq -n '[range(100) as $r | [range(20) as $c | {type: "raw_text", text: ("r\($r)c\($c)-" + ("x" * (10 + (($r * 20 + $c) % 91))))}]]' \
		>"$rows_file"

	SMOKE_TEST_PAYLOAD_FILE=$(mktemp "${BATS_TEST_TMPDIR}/smoke-tests.smoke-payload.XXXXXX")
	jq -n \
		--slurpfile rows "$rows_file" \
		--arg channel "$CHANNEL" \
		--arg token "$REAL_TOKEN" \
		'{
			source: { slack_bot_user_oauth_token: $token },
			params: {
				channel: $channel,
				dry_run: "false",
				blocks: [{ table: { rows: $rows[0] } }]
			}
		}' >"$SMOKE_TEST_PAYLOAD_FILE"
	export SMOKE_TEST_PAYLOAD_FILE

	local parsed_payload
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

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

@test "smoke_test:: image block with url title and block_id" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/image.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "image-with-url-title-and-block-id") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke_test:: image block with slack_file url" {
	skip "Requires real Slack file URL from actual file upload"

	local EXAMPLES_FILE="$GIT_ROOT/examples/image.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "image-with-slack-file-url") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke_test:: image block with slack_file id" {
	skip "Requires real Slack file ID from actual file upload"

	local EXAMPLES_FILE="$GIT_ROOT/examples/image.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "image-with-slack-file-id") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

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

@test "smoke_test:: markdown block" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/markdown.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "markdown-build-notification") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

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

@test "smoke_test:: header block with plain_text only" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/header.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "header-with-plain-text-only") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke_test:: header block with block_id and maximum text" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/header.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "header-with-block-id-and-maximum-text") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

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

@test "smoke_test:: context block with image and text elements" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/context.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "context-with-image-and-text-elements") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke_test:: context block with multiple text elements and block_id" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/context.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "context-with-multiple-text-elements-and-block-id") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

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

@test "smoke_test:: section block with mrkdwn text and button accessory" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/section.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "section-with-mrkdwn-text-and-button-accessory") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke_test:: section block with fields array and block_id" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/section.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "section-with-fields-array-and-block-id") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke_test:: section block with plain_text expand and image accessory" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/section.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "section-with-plain-text-expand-and-image-accessory") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

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

@test "smoke_test:: divider block basic separator" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/divider.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "divider-basic-separator") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke_test:: divider block with block_id separating sections" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/divider.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "divider-with-block-id-separating-sections") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

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

@test "smoke_test:: video block" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/video.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "basic-video") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

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

@test "smoke_test:: video-with-all-fields" {
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

@test "smoke_test:: rich-text sends rich-text-section-with-all-elements" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/rich-text.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "rich-text-section-with-all-elements") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke_test:: rich-text sends rich-text-attachment-with-color" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/rich-text.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "rich-text-attachment-with-color") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke_test:: rich-text sends rich-text-lists-with-all-options" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/rich-text.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "rich-text-lists-with-all-options") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke_test:: rich-text sends multiple-rich-text-blocks" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/rich-text.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "multiple-rich-text-blocks") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke_test:: rich-text sends rich-text-preformatted-and-quote" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/rich-text.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "rich-text-preformatted-and-quote") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke_test:: rich-text sends oversize-rich-text" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/rich-text.yaml"
	local line_text="This is some test content that will exceed the 4000 character limit for rich text blocks."
	local long_text_file
	long_text_file=$(mktemp smoke-tests.oversize-rich-text.XXXXXX.txt)
	trap 'rm -f "$long_text_file" 2>/dev/null || true' EXIT
	for i in {1..450}; do
		echo "$i: $line_text" >>"$long_text_file"
	done

	local long_text
	long_text=$(cat "$long_text_file")

	local blocks_json
	blocks_json=$(jq -n --arg text "$long_text" '[{"rich-text": {"elements": [{"type": "rich_text_section", "elements": [{"type": "text", "text": $text}]}]}}]')

	smoke_test_setup "$blocks_json"
	local parsed_payload
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		rm -f "$long_text_file"
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		rm -f "$long_text_file"
		return 1
	fi

	run send_notification "$parsed_payload"
	local test_result=$status

	rm -f "$long_text_file"
	trap - EXIT

	[[ "$test_result" -eq 0 ]]
}

########################################################
# File upload smoke tests
########################################################

@test "smoke_test:: uploads hello world file" {
	local hello_world_file
	hello_world_file=$(mktemp smoke-tests.hello-world.XXXXXX)
	trap 'rm -f "$hello_world_file" 2>/dev/null || true' EXIT
	echo "hello world" >"$hello_world_file"

	local blocks_json
	blocks_json=$(jq -n --arg path "$hello_world_file" '[{ "file": { "path": $path } }]')

	smoke_test_setup "$blocks_json"

	local parsed_payload
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		rm -f "$hello_world_file"
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		rm -f "$hello_world_file"
		return 1
	fi

	run send_notification "$parsed_payload"
	local test_result=$status

	rm -f "$hello_world_file"
	trap - EXIT

	[[ "$test_result" -eq 0 ]]
}

@test "smoke_test:: downloads Slack logo PNG and uploads it" {
	local slack_logo_file
	slack_logo_file=$(mktemp smoke-tests.slack-logo.XXXXXX.png)
	trap 'rm -f "$slack_logo_file" 2>/dev/null || true' EXIT

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
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		rm -f "$slack_logo_file"
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		rm -f "$slack_logo_file"
		return 1
	fi

	run send_notification "$parsed_payload"
	local test_result=$status

	rm -f "$slack_logo_file"
	trap - EXIT

	[[ "$test_result" -eq 0 ]]
}

@test "smoke_test:: multiple file blocks in blocks array" {
	local file1
	local file2
	file1=$(mktemp smoke-tests.file1.XXXXXX)
	file2=$(mktemp smoke-tests.file2.XXXXXX)
	trap 'rm -f "$file1" "$file2" 2>/dev/null || true' EXIT
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
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		rm -f "$file1" "$file2"
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		rm -f "$file1" "$file2"
		return 1
	fi

	run send_notification "$parsed_payload"
	local test_result=$status

	rm -f "$file1" "$file2"
	trap - EXIT

	[[ "$test_result" -eq 0 ]]
}

@test "smoke_test:: file block without title uses filename" {
	local test_file
	test_file=$(mktemp smoke-tests.test-file.XXXXXX.txt)
	trap 'rm -f "$test_file" 2>/dev/null || true' EXIT
	echo "Test content" >"$test_file"

	local blocks_json
	blocks_json=$(jq -n --arg path "$test_file" '[{ "file": { "path": $path } }]')

	smoke_test_setup "$blocks_json"

	local parsed_payload
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		rm -f "$test_file"
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		rm -f "$test_file"
		return 1
	fi

	run send_notification "$parsed_payload"
	local test_result=$status

	rm -f "$test_file"
	trap - EXIT

	[[ "$test_result" -eq 0 ]]
}

@test "smoke_test:: file block mixed with other blocks" {
	local test_file
	test_file=$(mktemp smoke-tests.test-file.XXXXXX)
	trap 'rm -f "$test_file" 2>/dev/null || true' EXIT
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
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		rm -f "$test_file"
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		rm -f "$test_file"
		return 1
	fi

	run send_notification "$parsed_payload"
	local test_result=$status

	rm -f "$test_file"
	trap - EXIT

	[[ "$test_result" -eq 0 ]]
}

@test "smoke_test:: file permissions debug after upload" {
	local test_file
	test_file=$(mktemp smoke-tests.test-file.XXXXXX.txt)
	trap 'rm -f "$test_file" 2>/dev/null || true' EXIT
	echo "Permission test content" >"$test_file"

	local initial_perms
	initial_perms=$(stat -c "%a %A" "$test_file" 2>/dev/null || stat -f "%OLp %Sp" "$test_file" 2>/dev/null || echo "unknown")
	echo "Initial file permissions: $initial_perms" >&2

	local blocks_json
	blocks_json=$(jq -n --arg path "$test_file" '[{ "file": { "path": $path, "title": "Permission Test File" } }]')

	smoke_test_setup "$blocks_json"

	local parsed_payload
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		rm -f "$test_file"
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

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
	trap - EXIT

	[[ "$test_result" -eq 0 ]]
}

########################################################
# Ephemeral and chat.update smoke tests
########################################################

@test "smoke_test:: chat.postEphemeral via params.ephemeral_user" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/ephemeral.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "ephemeral-basic-blocks") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup_ephemeral "$blocks_json"
	local parsed_payload
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke_test:: post_message then chat.update" {
	if [[ -z "$REAL_TOKEN" ]]; then
		skip "SLACK_BOT_USER_OAUTH_TOKEN not set"
	fi

	local token="$REAL_TOKEN"
	local dry_run="false"
	local post_payload_file
	local out_file
	local update_payload_file

	post_payload_file=$(mktemp "${BATS_TEST_TMPDIR}/smoke-update-post.XXXXXX")
	out_file=$(mktemp "${BATS_TEST_TMPDIR}/smoke-update-out.XXXXXX")
	update_payload_file=$(mktemp "${BATS_TEST_TMPDIR}/smoke-update-put.XXXXXX")
	trap 'rm -f "$post_payload_file" "$out_file" "$update_payload_file" 2>/dev/null || true' EXIT

	jq -n \
		--arg token "$token" \
		--arg channel "$CHANNEL" \
		--arg dry_run "$dry_run" \
		'{
			source: { slack_bot_user_oauth_token: $token },
			params: {
				channel: $channel,
				dry_run: $dry_run,
				text: "smoke test post for chat.update",
				blocks: [
					{
						section: {
							type: "text",
							text: { type: "mrkdwn", text: "smoke: message before chat.update" }
						}
					}
				]
			}
		}' >"$post_payload_file"

	if ! env SEND_TO_SLACK_OUTPUT="$out_file" "$SEND_TO_SLACK_SCRIPT" <"$post_payload_file"; then
		echo "smoke post_message then chat.update:: first send-to-slack run failed" >&2
		return 1
	fi

	local message_ts
	message_ts=$(jq -r '.version.message_ts // empty' "$out_file")
	if [[ -z "$message_ts" || "$message_ts" == "null" ]]; then
		echo "smoke post_message then chat.update:: missing version.message_ts" >&2
		cat "$out_file" >&2
		return 1
	fi

	local update_channel
	update_channel=$(jq -r 'first((.metadata // [])[] | select(.name == "channel") | .value) // empty' "$out_file")
	if [[ -z "$update_channel" || "$update_channel" == "null" ]]; then
		update_channel="$CHANNEL"
	fi

	jq -n \
		--arg token "$token" \
		--arg channel "$update_channel" \
		--arg dry_run "$dry_run" \
		--arg message_ts "$message_ts" \
		'{
			source: { slack_bot_user_oauth_token: $token },
			params: {
				channel: $channel,
				dry_run: $dry_run,
				message_ts: $message_ts,
				text: "smoke test after chat.update",
				blocks: [
					{
						section: {
							type: "text",
							text: { type: "mrkdwn", text: "smoke: message after chat.update" }
						}
					}
				]
			}
		}' >"$update_payload_file"

	local update_output
	if ! update_output=$(env SEND_TO_SLACK_OUTPUT="$out_file" "$SEND_TO_SLACK_SCRIPT" <"$update_payload_file" 2>&1); then
		echo "smoke post_message then chat.update:: second send-to-slack run failed" >&2
		echo "$update_output" >&2
		return 1
	fi

	echo "$update_output" | grep -q "main:: updating existing Slack message via chat.update"
	echo "$update_output" | grep -q "main:: finished running send-to-slack.sh successfully"
}

########################################################
# Parse payload smoke tests
########################################################

@test "smoke_test:: params.raw" {
	local raw_params
	raw_params=$(jq -n --arg channel "$CHANNEL" '{"channel": $channel, "dry_run": "false", "blocks": [{"section": {"type": "text", "text": {"type": "plain_text", "text": "Smoke test for params.raw"}}}] }')

	local params_json
	params_json=$(jq -n --arg raw "$raw_params" '{ raw: $raw }')

	SMOKE_TEST_PAYLOAD_FILE=$(mktemp "${BATS_TEST_TMPDIR}/smoke-tests.smoke-payload.XXXXXX")

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

	echo "$payload_output" | jq -e --arg channel "$CHANNEL" '.channel == $channel' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].type == "section"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].text.type == "plain_text"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].text.text == "Smoke test for params.raw"' >/dev/null
}

@test "smoke_test:: params.from_file" {
	local payload_file
	payload_file=$(mktemp smoke-tests.params-file.XXXXXX)
	trap 'rm -f "$payload_file" 2>/dev/null || true' EXIT

	jq -n --arg channel "$CHANNEL" \
		'{
			channel: $channel,
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

	SMOKE_TEST_PAYLOAD_FILE=$(mktemp "${BATS_TEST_TMPDIR}/smoke-tests.smoke-payload.XXXXXX")

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

	echo "$payload_output" | jq -e --arg channel "$CHANNEL" '.channel == $channel' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].type == "section"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].text.type == "plain_text"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].text.text == "Smoke test for params.from_file"' >/dev/null

	rm -f "$payload_file"
	trap - EXIT
}

@test "smoke_test:: blocks from_file" {
	local block_file
	block_file="$GIT_ROOT/examples/fixtures/blocks-from-file.json"

	local blocks_json
	blocks_json=$(jq -n --arg file "$block_file" '[{ from_file: $file }]')

	smoke_test_setup "$blocks_json"

	local payload_output
	if ! payload_output=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		return 1
	fi

	if [[ -z "$payload_output" ]]; then
		echo "payload output is empty" >&2
		return 1
	fi

	echo "$payload_output" | jq -e --arg channel "$CHANNEL" '.channel == $channel' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].type == "section"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].text.type == "plain_text"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].text.text == "Blocks loaded from file"' >/dev/null
}

@test "smoke_test:: blocks from_file 2" {
	local block_file
	block_file="$GIT_ROOT/examples/fixtures/blocks-from-file-2.json"

	local blocks_json
	blocks_json=$(jq -n --arg file "$block_file" '[{ from_file: $file }]')

	smoke_test_setup "$blocks_json"

	local payload_output
	if ! payload_output=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		return 1
	fi

	if [[ -z "$payload_output" ]]; then
		echo "payload output is empty" >&2
		return 1
	fi

	echo "$payload_output" | jq -e --arg channel "$CHANNEL" '.channel == $channel' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].type == "context"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].elements[0].text == "Additional block from second file"' >/dev/null
}

@test "smoke_test:: blocks from_file 3" {
	local block_file
	block_file="$GIT_ROOT/examples/fixtures/blocks-from-file-3.json"
	mkdir -p output
	echo "Example file for blocks-from-file-3" >output/example.txt
	trap 'rm -rf output' EXIT

	local blocks_json
	blocks_json=$(jq -n --arg file "$block_file" '[{ from_file: $file }]')

	smoke_test_setup "$blocks_json"

	local payload_output
	if ! payload_output=$(parse_payload "$SMOKE_TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		rm -rf output
		return 1
	fi

	if [[ -z "$payload_output" ]]; then
		echo "payload output is empty" >&2
		rm -rf output
		return 1
	fi

	echo "$payload_output" | jq -e --arg channel "$CHANNEL" '.channel == $channel' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].type == "header"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].text.text == "All Block Types from File"' >/dev/null

	rm -rf output
	trap - EXIT
}

########################################################
# Bot identity smoke tests
########################################################

@test "smoke_test:: bot identity username and icon_emoji from example" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/bot-identity.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "notify-deploy-bot") | .plan[0].params.blocks' "$EXAMPLES_FILE")

	smoke_test_setup_bot_identity "$blocks_json" "Deploy Bot" ":rocket:"

	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
	local parsed_payload
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	echo "$parsed_payload" | jq -e '.username == "Deploy Bot"' >/dev/null
	echo "$parsed_payload" | jq -e '.icon_emoji == ":rocket:"' >/dev/null

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke_test:: bot identity username and icon_url from example" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/bot-identity.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "notify-with-icon-url") | .plan[0].params.blocks' "$EXAMPLES_FILE")
	local icon_url
	icon_url=$(yq -o json -r '.jobs[] | select(.name == "notify-with-icon-url") | .plan[0].params.icon_url' "$EXAMPLES_FILE")

	smoke_test_setup_bot_identity_icon_url "$blocks_json" "Icon URL Bot" "$icon_url"

	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
	local parsed_payload
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	echo "$parsed_payload" | jq -e '.username == "Icon URL Bot"' >/dev/null
	echo "$parsed_payload" | jq -e --arg u "$icon_url" '.icon_url == $u' >/dev/null
	echo "$parsed_payload" | jq -e 'has("icon_emoji") | not' >/dev/null

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

########################################################
# Incoming Webhook smoke tests
########################################################

@test "smoke_test:: webhook posts section block" {
	local blocks_json
	blocks_json=$(jq -n '[{
		section: {
			type: "text",
			text: {
				type: "plain_text",
				text: "Smoke test Incoming Webhook delivery"
			}
		}
	}]')

	smoke_test_setup_webhook "$blocks_json"
	unset SLACK_BOT_USER_OAUTH_TOKEN
	local parsed_payload
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke_test:: webhook posts blocks from webhook example yaml" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/webhook-slack.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r \
		'.jobs[] | select(.name == "notify-via-slack-webhook") | .plan[0].params.blocks' \
		"$EXAMPLES_FILE")

	smoke_test_setup_webhook "$blocks_json"
	unset SLACK_BOT_USER_OAUTH_TOKEN
	local parsed_payload
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

@test "smoke_test:: webhook posts blocks from webhook-no-channel example yaml" {
	local EXAMPLES_FILE="$GIT_ROOT/examples/webhook-no-channel.yaml"
	local blocks_json
	blocks_json=$(yq -o json -r \
		'.jobs[] | select(.name == "notify-webhook-without-channel") | .plan[0].params.blocks' \
		"$EXAMPLES_FILE")

	smoke_test_setup_webhook "$blocks_json"
	unset SLACK_BOT_USER_OAUTH_TOKEN
	unset CHANNEL
	local parsed_payload
	if ! smoke_parse_payload_capture "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi
	parsed_payload="$SMOKE_PARSED_PAYLOAD"

	if [[ -z "$parsed_payload" ]]; then
		echo "parsed_payload is empty" >&2
		return 1
	fi

	echo "$parsed_payload" | jq -e 'has("channel") | not' >/dev/null

	run send_notification "$parsed_payload"
	[[ "$status" -eq 0 ]]
}

########################################################
# Webhook incompatibility: ephemeral and chat.update
########################################################

@test "smoke_test:: webhook rejects params.ephemeral_user at parse time" {
	if [[ -z "${REAL_WEBHOOK_URL:-}" ]]; then
		skip "SLACK_WEBHOOK_URL not set"
	fi

	local webhook_url="$REAL_WEBHOOK_URL"
	local dry_run="true"

	SMOKE_TEST_PAYLOAD_FILE=$(mktemp "${BATS_TEST_TMPDIR}/smoke-tests.webhook-ephemeral-reject.XXXXXX")

	jq -n \
		--arg url "$webhook_url" \
		--arg dry_run "$dry_run" \
		--arg ephemeral_user "U0123456789" \
		'{
			source: { webhook_url: $url },
			params: {
				dry_run: $dry_run,
				ephemeral_user: $ephemeral_user,
				blocks: [
					{
						section: {
							type: "text",
							text: {
								type: "plain_text",
								text: "webhook must not combine with ephemeral_user"
							}
						}
					}
				]
			}
		}' >"$SMOKE_TEST_PAYLOAD_FILE"

	unset SLACK_BOT_USER_OAUTH_TOKEN
	run parse_payload "$SMOKE_TEST_PAYLOAD_FILE"
	[[ "$status" -ne 0 ]]
	echo "$output" | grep -q "load_configuration:: params.ephemeral_user requires API delivery with a bot token, not webhook"
}

@test "smoke_test:: webhook rejects params.username at parse time" {
	if [[ -z "${REAL_WEBHOOK_URL:-}" ]]; then
		skip "SLACK_WEBHOOK_URL not set"
	fi

	local webhook_url="$REAL_WEBHOOK_URL"
	local dry_run="true"

	SMOKE_TEST_PAYLOAD_FILE=$(mktemp "${BATS_TEST_TMPDIR}/smoke-tests.webhook-username-reject.XXXXXX")

	jq -n \
		--arg url "$webhook_url" \
		--arg dry_run "$dry_run" \
		'{
			source: { webhook_url: $url },
			params: {
				dry_run: $dry_run,
				username: "Deploy Bot",
				blocks: [
					{
						section: {
							type: "text",
							text: {
								type: "plain_text",
								text: "webhook must not combine with username"
							}
						}
					}
				]
			}
		}' >"$SMOKE_TEST_PAYLOAD_FILE"

	unset SLACK_BOT_USER_OAUTH_TOKEN
	run parse_payload "$SMOKE_TEST_PAYLOAD_FILE"
	[[ "$status" -ne 0 ]]
	echo "$output" | grep -q "load_configuration:: params.username, params.icon_emoji, and params.icon_url require API delivery with a bot token, not webhook"
}

@test "smoke_test:: webhook rejects params.message_ts" {
	if [[ -z "${REAL_WEBHOOK_URL:-}" ]]; then
		skip "SLACK_WEBHOOK_URL not set"
	fi

	local webhook_url="$REAL_WEBHOOK_URL"
	local dry_run="true"
	local payload_file

	payload_file=$(mktemp "${BATS_TEST_TMPDIR}/smoke-tests.webhook-update-reject.XXXXXX")
	trap 'rm -f "$payload_file" 2>/dev/null || true' RETURN

	jq -n \
		--arg url "$webhook_url" \
		--arg dry_run "$dry_run" \
		--arg channel "$CHANNEL" \
		--arg message_ts "1234567890.000001" \
		'{
			source: { webhook_url: $url },
			params: {
				channel: $channel,
				dry_run: $dry_run,
				message_ts: $message_ts,
				blocks: [
					{
						section: {
							type: "text",
							text: {
								type: "plain_text",
								text: "webhook must not combine with message_ts"
							}
						}
					}
				]
			}
		}' >"$payload_file"

	run env -u SLACK_BOT_USER_OAUTH_TOKEN "$SEND_TO_SLACK_SCRIPT" <"$payload_file"
	[[ "$status" -ne 0 ]]
	echo "$output" | grep -q "main:: params.message_ts requires API delivery, not webhook"
}
