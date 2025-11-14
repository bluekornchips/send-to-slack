#!/usr/bin/env bats
#
# Test file for bin/parse-payload.sh
# Tests the new color-based attachment behavior
#

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		echo "Failed to get git root" >&2
		exit 1
	fi

	SCRIPT="$GIT_ROOT/bin/parse-payload.sh"
	if [[ ! -f "$SCRIPT" ]]; then
		echo "Script not found: $SCRIPT" >&2
		exit 1
	fi

	if [[ -n "$SLACK_BOT_USER_OAUTH_TOKEN" ]]; then
		REAL_TOKEN="$SLACK_BOT_USER_OAUTH_TOKEN"
		export REAL_TOKEN
	fi

	RICH_TEXT_EXAMPLES_FILE="$GIT_ROOT/examples/rich-text.yaml"

	export GIT_ROOT
	export SCRIPT
	export RICH_TEXT_EXAMPLES_FILE

	return 0
}

setup() {

	source "$SCRIPT"

	SEND_TO_SLACK_ROOT="$GIT_ROOT"
	export SEND_TO_SLACK_ROOT

	TEST_PAYLOAD_FILE=$(mktemp)
	export TEST_PAYLOAD_FILE

	chmod 0600 "${TEST_PAYLOAD_FILE}"
	create_test_payload

	SLACK_BOT_USER_OAUTH_TOKEN="xoxb-test-token"
	CHANNEL="main"
	DRY_RUN="true"

	export SLACK_BOT_USER_OAUTH_TOKEN
	export CHANNEL
	export DRY_RUN

	return 0
}

teardown() {
	[[ -n "$TEST_PAYLOAD_FILE" ]] && rm -f "$TEST_PAYLOAD_FILE"
	return 0
}

########################################################
# Helpers
########################################################

create_test_payload() {
	local blocks_json
	blocks_json=$(yq -o json <<<"$BLOCKS")

	jq -n \
		--argjson blocks "$blocks_json" \
		--arg channel "$CHANNEL" \
		--arg dry_run "$DRY_RUN" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				blocks: $blocks,
				dry_run: true
			}
		}' >"$TEST_PAYLOAD_FILE"
}

########################################################
# create_block
########################################################
@test "create_block:: no input" {
	run create_block
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "input is required"
}

@test "create_block:: invalid JSON" {
	run create_block "invalid json"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "must be valid JSON"
}

@test "create_block:: unsupported block type" {
	local block
	block=$(jq -n '{"type": "unsupported"}')

	run create_block "$block"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "unsupported block type"
}

@test "create_block:: basic" {
	local block_type block_value
	block_type=$(yq -r '.jobs[] | select(.name == "basic") | .plan[0].params.blocks[0] | keys[0]' "$RICH_TEXT_EXAMPLES_FILE")
	block_value=$(yq -o json -r '.jobs[] | select(.name == "basic") | .plan[0].params.blocks[0].'"$block_type" "$RICH_TEXT_EXAMPLES_FILE")

	run create_block "$block_value" "$block_type"
	[[ "$status" -eq 0 ]]
}

@test "create_block:: basic-attachment" {
	local block_type block_value
	block_type=$(yq -r '.jobs[] | select(.name == "basic-attachment") | .plan[0].params.blocks[0] | keys[0]' "$RICH_TEXT_EXAMPLES_FILE")
	block_value=$(yq -o json -r '.jobs[] | select(.name == "basic-attachment") | .plan[0].params.blocks[0].'"$block_type" "$RICH_TEXT_EXAMPLES_FILE")

	run create_block "$block_value" "$block_type"
	[[ "$status" -eq 0 ]]
}

@test "create_block:: two-rich-text-blocks" {
	local block_type block_value
	block_type=$(yq -r '.jobs[] | select(.name == "two-rich-text-blocks") | .plan[0].params.blocks[0] | keys[0]' "$RICH_TEXT_EXAMPLES_FILE")
	block_value=$(yq -o json -r '.jobs[] | select(.name == "two-rich-text-blocks") | .plan[0].params.blocks[0].'"$block_type" "$RICH_TEXT_EXAMPLES_FILE")

	run create_block "$block_value" "$block_type"
	[[ "$status" -eq 0 ]]
}

@test "create_block:: rich-text-block-and-attachment" {
	local block_type block_value
	block_type=$(yq -r '.jobs[] | select(.name == "rich-text-block-and-attachment") | .plan[0].params.blocks[0] | keys[0]' "$RICH_TEXT_EXAMPLES_FILE")
	block_value=$(yq -o json -r '.jobs[] | select(.name == "rich-text-block-and-attachment") | .plan[0].params.blocks[0].'"$block_type" "$RICH_TEXT_EXAMPLES_FILE")

	run create_block "$block_value" "$block_type"
	[[ "$status" -eq 0 ]]
}

########################################################
# parse_payload
########################################################

@test "parse_payload:: invalid json input" {
	local invalid_file
	invalid_file=$(mktemp)
	echo "invalid json" >"$invalid_file"

	run parse_payload "$invalid_file"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "invalid JSON"

	rm -f "$invalid_file"
}

@test "parse_payload:: missing slack_bot_user_oauth_token" {
	local test_payload
	test_payload=$(jq 'del(.source.slack_bot_user_oauth_token)' "$TEST_PAYLOAD_FILE")
	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "slack_bot_user_oauth_token is required"
}

@test "parse_payload:: missing channel" {
	local test_payload
	test_payload=$(jq 'del(.params.channel)' "$TEST_PAYLOAD_FILE")
	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "params.channel is required"
}

@test "parse_payload:: fallback to SLACK_BOT_USER_OAUTH_TOKEN env var when source missing" {
	local test_payload
	test_payload=$(jq '.params.blocks = [{"section": {"type": "text", "text": {"type": "plain_text", "text": "Test"}}}] | .params.channel = "test-channel" | del(.source)' "$TEST_PAYLOAD_FILE")
	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	SLACK_BOT_USER_OAUTH_TOKEN="env-token-value"
	CHANNEL="env-channel-value"
	DRY_RUN="false"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Source key not found in payload. Using SLACK_BOT_USER_OAUTH_TOKEN from environment variable"
	[[ "$SLACK_BOT_USER_OAUTH_TOKEN" == "env-token-value" ]]

	unset SLACK_BOT_USER_OAUTH_TOKEN
	unset CHANNEL
	unset DRY_RUN
}

@test "parse_payload:: fallback to CHANNEL env var when source missing" {
	local test_payload
	test_payload=$(jq '.params.blocks = [{"section": {"type": "text", "text": {"type": "plain_text", "text": "Test"}}}] | del(.source) | del(.params.channel)' "$TEST_PAYLOAD_FILE")
	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	SLACK_BOT_USER_OAUTH_TOKEN="env-token-value"
	CHANNEL="env-channel-value"
	DRY_RUN="false"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Source key not found in payload. Using SLACK_BOT_USER_OAUTH_TOKEN from environment variable"
	echo "$output" | grep -q "Source key not found in payload. Using CHANNEL from environment variable"
	[[ "$CHANNEL" == "env-channel-value" ]]

	unset SLACK_BOT_USER_OAUTH_TOKEN
	unset CHANNEL
	unset DRY_RUN
}

@test "parse_payload:: fallback to DRY_RUN env var when source missing" {
	local test_payload
	test_payload=$(jq '.params.blocks = [{"section": {"type": "text", "text": {"type": "plain_text", "text": "Test"}}}] | .params.channel = "test-channel" | del(.source) | del(.params.dry_run)' "$TEST_PAYLOAD_FILE")
	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	SLACK_BOT_USER_OAUTH_TOKEN="env-token-value"
	CHANNEL="test-channel"
	DRY_RUN="true"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Source key not found in payload. Using SLACK_BOT_USER_OAUTH_TOKEN from environment variable"
	echo "$output" | grep -q "Source key not found in payload. Using DRY_RUN from environment variable"
	[[ "$DRY_RUN" == "true" ]]

	unset SLACK_BOT_USER_OAUTH_TOKEN
	unset CHANNEL
	unset DRY_RUN
}

@test "parse_payload:: fallback to all env vars when source missing" {
	local test_payload
	test_payload=$(jq '.params.blocks = [{"section": {"type": "text", "text": {"type": "plain_text", "text": "Test"}}}] | del(.source) | del(.params.channel) | del(.params.dry_run)' "$TEST_PAYLOAD_FILE")
	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	SLACK_BOT_USER_OAUTH_TOKEN="env-token-value"
	CHANNEL="env-channel-value"
	DRY_RUN="true"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Source key not found in payload. Using SLACK_BOT_USER_OAUTH_TOKEN from environment variable"
	echo "$output" | grep -q "Source key not found in payload. Using CHANNEL from environment variable"
	echo "$output" | grep -q "Source key not found in payload. Using DRY_RUN from environment variable"
	[[ "$SLACK_BOT_USER_OAUTH_TOKEN" == "env-token-value" ]]
	[[ "$CHANNEL" == "env-channel-value" ]]
	[[ "$DRY_RUN" == "true" ]]

	unset SLACK_BOT_USER_OAUTH_TOKEN
	unset CHANNEL
	unset DRY_RUN
}

@test "parse_payload:: fails when source missing and SLACK_BOT_USER_OAUTH_TOKEN env var not set" {
	local test_payload
	test_payload=$(jq '.params.blocks = [{"section": {"type": "text", "text": {"type": "plain_text", "text": "Test"}}}] | .params.channel = "test-channel" | del(.source)' "$TEST_PAYLOAD_FILE")
	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	unset SLACK_BOT_USER_OAUTH_TOKEN
	CHANNEL="test-channel"
	DRY_RUN="false"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "SLACK_BOT_USER_OAUTH_TOKEN is required. Not found in payload source or environment"

	unset CHANNEL
	unset DRY_RUN
}

@test "parse_payload:: fails when source missing and CHANNEL env var not set" {
	local test_payload
	test_payload=$(jq '.params.blocks = [{"section": {"type": "text", "text": {"type": "plain_text", "text": "Test"}}}] | del(.source) | del(.params.channel)' "$TEST_PAYLOAD_FILE")
	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	SLACK_BOT_USER_OAUTH_TOKEN="env-token-value"
	unset CHANNEL
	DRY_RUN="false"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "Source key not found in payload. Using SLACK_BOT_USER_OAUTH_TOKEN from environment variable"
	echo "$output" | grep -q "params.channel is required. Not found in payload or environment"

	unset SLACK_BOT_USER_OAUTH_TOKEN
	unset DRY_RUN
}

@test "parse_payload:: source takes precedence over env vars" {
	local test_payload
	test_payload=$(jq '.params.blocks = [{"section": {"type": "text", "text": {"type": "plain_text", "text": "Test"}}}] | .params.channel = "test-channel" | .source.slack_bot_user_oauth_token = "payload-token-value"' "$TEST_PAYLOAD_FILE")
	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	# Call parse_payload directly to check exported variables
	# Capture output to temp file to avoid subshell issues
	local output_file
	output_file=$(mktemp)
	if ! parse_payload "$TEST_PAYLOAD_FILE" >"$output_file" 2>&1; then
		cat "$output_file"
		rm -f "$output_file"
		echo "parse_payload failed" >&2
		return 1
	fi
	local output
	output=$(cat "$output_file")
	rm -f "$output_file"
	# Should NOT use env vars when source exists
	echo "$output" | grep -vq "Source key not found in payload. Using SLACK_BOT_USER_OAUTH_TOKEN from environment variable"
	echo "$output" | grep -vq "Source key not found in payload. Using CHANNEL from environment variable"
	echo "$output" | grep -vq "Source key not found in payload. Using DRY_RUN from environment variable"
	# Should use payload values
	[[ "$SLACK_BOT_USER_OAUTH_TOKEN" == "payload-token-value" ]]

	unset SLACK_BOT_USER_OAUTH_TOKEN
	unset CHANNEL
	unset DRY_RUN
}

@test "parse_payload:: params.raw" {
	local raw_params
	raw_params='{"channel": "raw-channel", "blocks": [{"section": {"type": "text", "text": {"type": "plain_text", "text": "Raw message"}}}]}'

	local test_payload
	test_payload=$(jq -n \
		--arg raw "$raw_params" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				raw: $raw
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "using raw payload"
}

@test "parse_payload:: params.raw invalid json" {
	local test_payload
	test_payload=$(jq -n '{ params: { raw: "invalid json" } }')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "raw payload is not valid JSON"
}

@test "parse_payload:: params.from_file" {
	local payload_file
	payload_file=$(mktemp)

	# File contains only params (source is preserved from test payload)
	jq -n \
		'{
			channel: "file-channel",
			blocks: [{
				section: {
					type: "text",
					text: { type: "plain_text", text: "File message" }
				}
			}]
		}' >"$payload_file"

	# Test payload must include source section
	local test_payload
	test_payload=$(jq -n \
		--arg file "$payload_file" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				from_file: $file
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "using payload from file"

	rm -f "$payload_file"
}

@test "parse_payload:: params.from_file not found" {
	local test_payload
	test_payload=$(jq -n '{ params: { from_file: "/nonexistent/file.json" } }')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "payload from file not found"
}

@test "parse_payload:: params.from_file invalid json" {
	local payload_file
	payload_file=$(mktemp)
	echo "invalid json" >"$payload_file"

	local test_payload
	test_payload=$(jq -n --arg file "$payload_file" '{ params: { from_file: $file } }')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "payload file contains invalid JSON"

	rm -f "$payload_file"
}

@test "parse_payload:: block count exceeds 50 blocks limit" {
	# Create a payload with 51 blocks
	local blocks_array
	blocks_array=$(jq -n '[range(51) | {"section": {"type": "text", "text": {"type": "plain_text", "text": "Block \(.)"}}}]')

	local test_payload
	test_payload=$(jq -n \
		--argjson blocks "$blocks_array" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: "test-channel",
				blocks: $blocks
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "block count.*exceeds Slack's maximum of 50 blocks"
}

@test "parse_payload:: block count exactly at 50 blocks limit succeeds" {
	# Create a payload with exactly 50 blocks
	local blocks_array
	blocks_array=$(jq -n '[range(50) | {"section": {"type": "text", "text": {"type": "plain_text", "text": "Block \(.)"}}}]')

	local test_payload
	test_payload=$(jq -n \
		--argjson blocks "$blocks_array" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: "test-channel",
				blocks: $blocks
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
}

@test "parse_payload:: attachment count exceeds 20 attachments limit" {
	local colored_blocks
	colored_blocks=$(jq -n '[range(21) | {
		section: {
			type: "text",
			text: {type: "plain_text", text: "Colored block \(.)"},
			color: "#FF0000"
		}
	}]')

	local test_payload
	test_payload=$(jq -n \
		--argjson colored "$colored_blocks" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: "test-channel",
				blocks: $colored
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "attachment count.*exceeds Slack's maximum of 20 attachments"
}

@test "parse_payload:: attachment count exactly at 20 attachments limit succeeds" {
	# Create a payload with exactly 20 blocks with color (which become attachments)
	local colored_blocks
	colored_blocks=$(jq -n '[range(20) | {
		section: {
			type: "text",
			text: {type: "plain_text", text: "Colored block \(.)"},
			color: "#FF0000"
		}
	}]')

	local test_payload
	test_payload=$(jq -n \
		--argjson colored "$colored_blocks" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: "test-channel",
				blocks: $colored
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
}

@test "parse_payload:: total block count with attachments exceeds 50 blocks limit" {
	local regular_blocks
	regular_blocks=$(jq -n '[range(31) | {"section": {"type": "text", "text": {"type": "plain_text", "text": "Block \(.)"}}}]')

	# Create 20 blocks with color property (these become attachments, staying within limit)
	local colored_blocks
	colored_blocks=$(jq -n '[range(20) | {
		section: {
			type: "text",
			text: {type: "plain_text", text: "Colored block \(.)"},
			color: "#FF0000"
		}
	}]')

	local test_payload
	test_payload=$(jq -n \
		--argjson regular "$regular_blocks" \
		--argjson colored "$colored_blocks" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: "test-channel",
				blocks: ($regular + $colored)
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "total block count.*exceeds Slack's maximum of 50 blocks"
}

@test "parse_payload:: text field exceeds 40000 characters limit" {
	# Generate 40,001 characters using awk
	local long_text
	long_text=$(awk 'BEGIN {for(i=0;i<40001;i++) printf "a"}')

	local test_payload
	test_payload=$(jq -n \
		--arg text "$long_text" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: "test-channel",
				blocks: [{"section": {"type": "text", "text": {"type": "plain_text", "text": "Test"}}}],
				text: $text
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "text field length.*exceeds Slack's maximum of 40000 characters"
}

@test "parse_payload:: text field exactly at 40000 characters limit succeeds" {
	# Generate exactly 40,000 characters using awk
	local long_text
	long_text=$(awk 'BEGIN {for(i=0;i<40000;i++) printf "a"}')

	local test_payload
	test_payload=$(jq -n \
		--arg text "$long_text" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: "test-channel",
				blocks: [{"section": {"type": "text", "text": {"type": "plain_text", "text": "Test"}}}],
				text: $text
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
}

@test "parse_payload:: text field is added to payload when provided" {
	local test_text="Test message text"

	local test_payload
	test_payload=$(jq -n \
		--arg text "$test_text" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: "test-channel",
				blocks: [{"section": {"type": "text", "text": {"type": "plain_text", "text": "Test"}}}],
				text: $text
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	# Call parse_payload directly so PAYLOAD export is available
	if ! parse_payload "$TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi

	[[ -n "$PAYLOAD" ]]
	echo "$PAYLOAD" | jq -e --arg text "$test_text" '.text == $text' >/dev/null
}

########################################################
# Smoke Tests
########################################################

smoke_test_setup() {
	local params_json="$1"

	if [[ "$SMOKE_TEST" != "true" ]]; then
		skip "SMOKE_TEST is not set"
	fi

	if [[ -z "$REAL_TOKEN" ]]; then
		skip "SLACK_BOT_USER_OAUTH_TOKEN not set"
	fi

	local dry_run="false"
	local channel="notification-testing"

	SMOKE_TEST_PAYLOAD_FILE=$(mktemp)
	chmod 0600 "${SMOKE_TEST_PAYLOAD_FILE}"

	jq -n \
		--arg token "$REAL_TOKEN" \
		--arg channel "$channel" \
		--arg dry_run "$dry_run" \
		--argjson params "$params_json" \
		'{
			source: {
				slack_bot_user_oauth_token: $token
			},
			params: $params
		}' >"$SMOKE_TEST_PAYLOAD_FILE"

	export SMOKE_TEST_PAYLOAD_FILE
}

@test "smoke test, params.raw" {
	local raw_params
	raw_params='{"channel": "notification-testing", "dry_run": "false", "blocks": [{"section": {"type": "text", "text": {"type": "plain_text", "text": "Smoke test for params.raw"}}}] }'

	local params_json
	params_json=$(jq -n --arg raw "$raw_params" '{ raw: $raw }')

	smoke_test_setup "$params_json"
	if ! parse_payload "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi

	if [[ -z "$PAYLOAD" ]]; then
		echo "PAYLOAD is not set" >&2
		return 1
	fi

	echo "$PAYLOAD" | jq -e '.channel == "notification-testing"' >/dev/null
	echo "$PAYLOAD" | jq -e '.blocks[0].type == "section"' >/dev/null
	echo "$PAYLOAD" | jq -e '.blocks[0].text.type == "plain_text"' >/dev/null
	echo "$PAYLOAD" | jq -e '.blocks[0].text.text == "Smoke test for params.raw"' >/dev/null
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

	smoke_test_setup "$params_json"
	if ! parse_payload "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		return 1
	fi

	if [[ -z "$PAYLOAD" ]]; then
		echo "PAYLOAD is not set" >&2
		return 1
	fi

	echo "$PAYLOAD" | jq -e '.channel == "notification-testing"' >/dev/null
	echo "$PAYLOAD" | jq -e '.blocks[0].type == "section"' >/dev/null
	echo "$PAYLOAD" | jq -e '.blocks[0].text.type == "plain_text"' >/dev/null
	echo "$PAYLOAD" | jq -e '.blocks[0].text.text == "Smoke test for params.from_file"' >/dev/null

	rm -f "$payload_file"
}
