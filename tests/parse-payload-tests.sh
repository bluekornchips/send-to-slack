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

	TEST_PAYLOAD_FILE=$(mktemp test-payload.XXXXXX)
	export TEST_PAYLOAD_FILE
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
	rm -f "${TEST_PAYLOAD_FILE}"
	[[ -n "$invalid_file" ]] && rm -f "$invalid_file"
	[[ -n "$output_file" ]] && rm -f "$output_file"
	[[ -n "$payload_file" ]] && rm -f "$payload_file"
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

@test "create_block:: rich-text-section-with-all-elements" {
	local block_type block_value
	block_type=$(yq -r '.jobs[] | select(.name == "rich-text-section-with-all-elements") | .plan[0].params.blocks[0] | keys[0]' "$RICH_TEXT_EXAMPLES_FILE")
	block_value=$(yq -o json -r '.jobs[] | select(.name == "rich-text-section-with-all-elements") | .plan[0].params.blocks[0].'"$block_type" "$RICH_TEXT_EXAMPLES_FILE")

	run create_block "$block_value" "$block_type"
	[[ "$status" -eq 0 ]]
}

@test "create_block:: rich-text-attachment-with-color" {
	local block_type block_value
	block_type=$(yq -r '.jobs[] | select(.name == "rich-text-attachment-with-color") | .plan[0].params.blocks[0] | keys[0]' "$RICH_TEXT_EXAMPLES_FILE")
	block_value=$(yq -o json -r '.jobs[] | select(.name == "rich-text-attachment-with-color") | .plan[0].params.blocks[0].'"$block_type" "$RICH_TEXT_EXAMPLES_FILE")

	run create_block "$block_value" "$block_type"
	[[ "$status" -eq 0 ]]
}

@test "create_block:: rich-text-lists-with-all-options" {
	local block_type block_value
	block_type=$(yq -r '.jobs[] | select(.name == "rich-text-lists-with-all-options") | .plan[0].params.blocks[0] | keys[0]' "$RICH_TEXT_EXAMPLES_FILE")
	block_value=$(yq -o json -r '.jobs[] | select(.name == "rich-text-lists-with-all-options") | .plan[0].params.blocks[0].'"$block_type" "$RICH_TEXT_EXAMPLES_FILE")

	run create_block "$block_value" "$block_type"
	[[ "$status" -eq 0 ]]
}

@test "create_block:: multiple-rich-text-blocks" {
	local block_type block_value
	block_type=$(yq -r '.jobs[] | select(.name == "multiple-rich-text-blocks") | .plan[0].params.blocks[0] | keys[0]' "$RICH_TEXT_EXAMPLES_FILE")
	block_value=$(yq -o json -r '.jobs[] | select(.name == "multiple-rich-text-blocks") | .plan[0].params.blocks[0].'"$block_type" "$RICH_TEXT_EXAMPLES_FILE")

	run create_block "$block_value" "$block_type"
	[[ "$status" -eq 0 ]]
}

@test "create_block:: rich-text-preformatted-and-quote" {
	local block_type block_value
	block_type=$(yq -r '.jobs[] | select(.name == "rich-text-preformatted-and-quote") | .plan[0].params.blocks[0] | keys[0]' "$RICH_TEXT_EXAMPLES_FILE")
	block_value=$(yq -o json -r '.jobs[] | select(.name == "rich-text-preformatted-and-quote") | .plan[0].params.blocks[0].'"$block_type" "$RICH_TEXT_EXAMPLES_FILE")

	run create_block "$block_value" "$block_type"
	[[ "$status" -eq 0 ]]
}

@test "create_block:: interpolates environment variables in block JSON" {
	# Set test environment variables to mimic concourse
	export BUILD_ID="12345"
	export BUILD_NAME="42"
	export BUILD_JOB_NAME="test-job"
	export BUILD_PIPELINE_NAME="test-pipeline"
	export BUILD_TEAM_NAME="main"
	export BUILD_CREATED_BY="test-user"
	export BUILD_PIPELINE_INSTANCE_VARS="{}"
	export ATC_EXTERNAL_URL="https://concourse.example.com"

	local block_input
	block_input=$(jq -n '{
		type: "text",
		text: {
			type: "mrkdwn",
			text: "Build ID: $BUILD_ID, Build Name: $BUILD_NAME"
		}
	}')

	run create_block "$block_input" "section"
	[[ "$status" -eq 0 ]]

	# Verify variables were interpolated
	echo "$output" | jq -e '.text.text | contains("12345")' >/dev/null
	echo "$output" | jq -e '.text.text | contains("42")' >/dev/null
	echo "$output" | jq -e '.text.text | contains("$BUILD_ID") == false' >/dev/null
	echo "$output" | jq -e '.text.text | contains("$BUILD_NAME") == false' >/dev/null

	unset BUILD_ID BUILD_NAME BUILD_JOB_NAME BUILD_PIPELINE_NAME BUILD_TEAM_NAME BUILD_CREATED_BY BUILD_PIPELINE_INSTANCE_VARS ATC_EXTERNAL_URL
}

@test "create_block:: interpolates all Concourse metadata variables" {
	export BUILD_ID="67890"
	export BUILD_NAME="99"
	export BUILD_JOB_NAME="metadata-job"
	export BUILD_PIPELINE_NAME="metadata-pipeline"
	export BUILD_TEAM_NAME="test-team"
	export BUILD_CREATED_BY="ci-user"
	export BUILD_PIPELINE_INSTANCE_VARS='{"env":"prod"}'
	export ATC_EXTERNAL_URL="https://ci.example.com"

	local block_input
	block_input=$(jq -n '{
		type: "fields",
		fields: [
			{type: "mrkdwn", text: "*BUILD_ID:*\n`$BUILD_ID`"},
			{type: "mrkdwn", text: "*BUILD_NAME:*\n`$BUILD_NAME`"},
			{type: "mrkdwn", text: "*BUILD_JOB_NAME:*\n`$BUILD_JOB_NAME`"},
			{type: "mrkdwn", text: "*BUILD_PIPELINE_NAME:*\n`$BUILD_PIPELINE_NAME`"},
			{type: "mrkdwn", text: "*BUILD_TEAM_NAME:*\n`$BUILD_TEAM_NAME`"},
			{type: "mrkdwn", text: "*BUILD_CREATED_BY:*\n`$BUILD_CREATED_BY`"},
			{type: "mrkdwn", text: "*BUILD_PIPELINE_INSTANCE_VARS:*\n`$BUILD_PIPELINE_INSTANCE_VARS`"},
			{type: "mrkdwn", text: "*ATC_EXTERNAL_URL:*\n<$ATC_EXTERNAL_URL|$ATC_EXTERNAL_URL>"}
		]
	}')

	run create_block "$block_input" "section"
	[[ "$status" -eq 0 ]]

	# Verify all variables were interpolated
	echo "$output" | jq -e '.fields[0].text | contains("67890")' >/dev/null
	echo "$output" | jq -e '.fields[1].text | contains("99")' >/dev/null
	echo "$output" | jq -e '.fields[2].text | contains("metadata-job")' >/dev/null
	echo "$output" | jq -e '.fields[3].text | contains("metadata-pipeline")' >/dev/null
	echo "$output" | jq -e '.fields[4].text | contains("test-team")' >/dev/null
	echo "$output" | jq -e '.fields[5].text | contains("ci-user")' >/dev/null
	echo "$output" | jq -e '.fields[6].text | contains("prod")' >/dev/null
	echo "$output" | jq -e '.fields[7].text | contains("https://ci.example.com")' >/dev/null

	# Verify variable references are gone
	echo "$output" | jq -e '.fields[0].text | contains("$BUILD_ID") == false' >/dev/null
	echo "$output" | jq -e '.fields[7].text | contains("$ATC_EXTERNAL_URL") == false' >/dev/null

	unset BUILD_ID BUILD_NAME BUILD_JOB_NAME BUILD_PIPELINE_NAME BUILD_TEAM_NAME BUILD_CREATED_BY BUILD_PIPELINE_INSTANCE_VARS ATC_EXTERNAL_URL
}

@test "create_block:: handles missing environment variables gracefully" {
	# Don't set any variables
	unset BUILD_ID BUILD_NAME 2>/dev/null || true

	local block_input
	block_input=$(jq -n '{
		type: "text",
		text: {
			type: "mrkdwn",
			text: "Build ID: $BUILD_ID"
		}
	}')

	run create_block "$block_input" "section"
	[[ "$status" -eq 0 ]]

	# Missing variables should be replaced with empty string by envsubst
	echo "$output" | jq -e '.text.text | contains("Build ID: ")' >/dev/null
}

@test "create_block:: interpolates variables in nested JSON structures" {
	export TEST_VAR="nested-value"

	local block_input
	block_input=$(jq -n '{
		elements: [
			{
				type: "rich_text_section",
				elements: [
					{type: "text", text: "Value: $TEST_VAR"}
				]
			}
		]
	}')

	run create_block "$block_input" "rich-text"
	[[ "$status" -eq 0 ]]

	# Verify variable was interpolated in nested structure
	echo "$output" | jq -e '.elements[0].elements[0].text | contains("nested-value")' >/dev/null
	echo "$output" | jq -e '.elements[0].elements[0].text | contains("$TEST_VAR") == false' >/dev/null

	unset TEST_VAR
}

@test "create_block:: preserves JSON structure after interpolation" {
	export BUILD_ID="12345"

	local block_input
	block_input=$(jq -n '{
		type: "fields",
		fields: [
			{type: "mrkdwn", text: "ID: $BUILD_ID"},
			{type: "plain_text", text: "Static text"}
		],
		block_id: "test-block"
	}')

	run create_block "$block_input" "section"
	[[ "$status" -eq 0 ]]

	# Verify JSON structure is preserved
	echo "$output" | jq -e '.type == "section"' >/dev/null
	echo "$output" | jq -e '.block_id == "test-block"' >/dev/null
	echo "$output" | jq -e '.fields | length == 2' >/dev/null
	echo "$output" | jq -e '.fields[0].type == "mrkdwn"' >/dev/null
	echo "$output" | jq -e '.fields[1].type == "plain_text"' >/dev/null
	echo "$output" | jq -e '.fields[1].text == "Static text"' >/dev/null

	unset BUILD_ID
}

@test "create_block:: handles variables with special characters" {
	export SPECIAL_VAR="value with spaces and special chars: !@#$%"

	local block_input
	block_input=$(jq -n '{
		type: "text",
		text: {
			type: "mrkdwn",
			text: "Special: $SPECIAL_VAR"
		}
	}')

	run create_block "$block_input" "section"
	[[ "$status" -eq 0 ]]

	# Verify variable was interpolated (envsubst handles special chars)
	echo "$output" | jq -e '.text.text | contains("value with spaces")' >/dev/null

	unset SPECIAL_VAR
}

@test "create_block:: interpolates variables in rich-text block" {
	export BUILD_ID="99999"
	export BUILD_NAME="100"

	local block_input
	block_input=$(jq -n '{
		elements: [
			{
				type: "rich_text_section",
				elements: [
					{type: "text", text: "Build $BUILD_ID"},
					{type: "text", text: " Name $BUILD_NAME"}
				]
			}
		]
	}')

	run create_block "$block_input" "rich-text"
	[[ "$status" -eq 0 ]]

	# Verify variables were interpolated
	echo "$output" | jq -e '.elements[0].elements[0].text | contains("99999")' >/dev/null
	echo "$output" | jq -e '.elements[0].elements[1].text | contains("100")' >/dev/null

	unset BUILD_ID BUILD_NAME
}

########################################################
# parse_payload
########################################################

@test "parse_payload:: invalid json input" {
	local invalid_file
	invalid_file=$(mktemp invalid-json.XXXXXX)
	trap 'rm -f "$invalid_file" 2>/dev/null || true' EXIT
	echo "invalid json" >"$invalid_file"

	run parse_payload "$invalid_file"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "invalid JSON"
	rm -f "$invalid_file"
	trap - EXIT

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
	output_file=$(mktemp output.XXXXXX)

	if ! parse_payload "$TEST_PAYLOAD_FILE" >"$output_file" 2>&1; then
		cat "$output_file"
		rm -f "$output_file"
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
	payload_file=$(mktemp params-file.XXXXXX)
	trap 'rm -f "$payload_file" 2>/dev/null || true' EXIT

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
	trap - EXIT
}

@test "parse_payload:: params.from_file not found" {
	local test_payload
	test_payload=$(jq -n '{ params: { from_file: "/nonexistent/file.json" } }')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "payload from file not found"

	rm -f "$payload_file"
	trap - EXIT
}

@test "parse_payload:: params.from_file invalid json" {
	local payload_file
	payload_file=$(mktemp invalid-params-file.XXXXXX)
	trap 'rm -f "$payload_file" 2>/dev/null || true' EXIT
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

	local payload_output
	if ! payload_output=$(parse_payload "$TEST_PAYLOAD_FILE"); then
		echo "parse_payload failed" >&2
		return 1
	fi

	[[ -n "$payload_output" ]]
	echo "$payload_output" | jq -e --arg text "$test_text" '.text == $text' >/dev/null
}

########################################################
# Thread Support Tests
########################################################

@test "parse_payload:: thread_ts is added to payload when provided" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		--arg thread_ts "1234567890.123456" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				thread_ts: $thread_ts,
				blocks: [{
					section: {
						type: "text",
						text: { type: "plain_text", text: "Test" }
					}
				}]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]

	local payload_output
	payload_output=$(parse_payload "$TEST_PAYLOAD_FILE")
	echo "$payload_output" | jq -e '.thread_ts == "1234567890.123456"' >/dev/null
}

@test "parse_payload:: thread_ts defaults to empty string when not provided" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				blocks: [{
					section: {
						type: "text",
						text: { type: "plain_text", text: "Test" }
					}
				}]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]

	local payload_output
	payload_output=$(parse_payload "$TEST_PAYLOAD_FILE")
	# thread_ts should not be present in payload when not provided
	echo "$payload_output" | jq -e 'has("thread_ts") == false' >/dev/null
}

@test "parse_payload:: create_thread defaults to false" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				blocks: [{
					section: {
						type: "text",
						text: { type: "plain_text", text: "Test" }
					}
				}]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	# Should not log warning about create_thread when it's false
	echo "$output" | grep -v -q "create_thread is true but only one block provided"
}

@test "parse_payload:: create_thread explicitly set to false" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				create_thread: false,
				blocks: [{
					section: {
						type: "text",
						text: { type: "plain_text", text: "Test" }
					}
				}]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	# Should not log warning about create_thread when explicitly set to false
	echo "$output" | grep -v -q "create_thread is true but only one block provided"
}

@test "parse_payload:: create_thread warning logged when only one block provided" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				create_thread: true,
				blocks: [{
					section: {
						type: "text",
						text: { type: "plain_text", text: "Test" }
					}
				}]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "create_thread is true but only one block provided, continuing as normal"
}

@test "parse_payload:: create_thread and thread_ts cannot both be set" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		--arg thread_ts "1234567890.123456" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				thread_ts: $thread_ts,
				create_thread: true,
				blocks: [
					{
						section: {
							type: "text",
							text: { type: "plain_text", text: "Test 1" }
						}
					},
					{
						section: {
							type: "text",
							text: { type: "plain_text", text: "Test 2" }
						}
					}
				]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "create_thread and thread_ts cannot both be set"
}

@test "parse_payload:: create_thread works correctly with multiple blocks" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				create_thread: true,
				blocks: [
					{
						section: {
							type: "text",
							text: { type: "plain_text", text: "Test 1" }
						}
					},
					{
						section: {
							type: "text",
							text: { type: "plain_text", text: "Test 2" }
						}
					}
				]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	# Should not log warning when multiple blocks are provided
	echo "$output" | grep -v -q "create_thread is true but only one block provided"
}

@test "parse_payload:: thread_ts empty string is not added to payload" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				thread_ts: "",
				blocks: [{
					section: {
						type: "text",
						text: { type: "plain_text", text: "Test" }
					}
				}]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]

	local payload_output
	payload_output=$(parse_payload "$TEST_PAYLOAD_FILE")
	# thread_ts should not be present in payload when empty string
	echo "$payload_output" | jq -e 'has("thread_ts") == false' >/dev/null
}

@test "parse_payload:: thread_ts converts Slack permalink to timestamp format" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		--arg thread_ts "https://tktestglobal.slack.com/archives/C06J34MSEPK/p1763178444659849" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				thread_ts: $thread_ts,
				blocks: [{
					section: {
						type: "text",
						text: { type: "plain_text", text: "Test" }
					}
				}]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]

	local payload_output
	payload_output=$(parse_payload "$TEST_PAYLOAD_FILE")
	# Permalink should be converted to timestamp format: 1763178444.659849
	echo "$payload_output" | jq -e '.thread_ts == "1763178444.659849"' >/dev/null
}

@test "parse_payload:: thread_ts permalink with http (not https) is supported" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		--arg thread_ts "http://workspace.slack.com/archives/C123456/p1763178444659849" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				thread_ts: $thread_ts,
				blocks: [{
					section: {
						type: "text",
						text: { type: "plain_text", text: "Test" }
					}
				}]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]

	local payload_output
	payload_output=$(parse_payload "$TEST_PAYLOAD_FILE")
	# Permalink should be converted to timestamp format
	echo "$payload_output" | jq -e '.thread_ts == "1763178444.659849"' >/dev/null
}

@test "parse_payload:: thread_ts converts 16-digit standalone number to timestamp format" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		--arg thread_ts "1763178414211229" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				thread_ts: $thread_ts,
				blocks: [{
					section: {
						type: "text",
						text: { type: "plain_text", text: "Test" }
					}
				}]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]

	local payload_output
	payload_output=$(parse_payload "$TEST_PAYLOAD_FILE")
	# 16-digit number should be converted to timestamp format: 1763178414.211229
	echo "$payload_output" | jq -e '.thread_ts == "1763178414.211229"' >/dev/null
}

@test "parse_payload:: thread_ts returns already-formatted timestamp as-is" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		--arg thread_ts "1763178414.211229" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				thread_ts: $thread_ts,
				blocks: [{
					section: {
						type: "text",
						text: { type: "plain_text", text: "Test" }
					}
				}]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]

	local payload_output
	payload_output=$(parse_payload "$TEST_PAYLOAD_FILE")
	# Already formatted timestamp should be returned as-is
	echo "$payload_output" | jq -e '.thread_ts == "1763178414.211229"' >/dev/null
}

########################################################
# Block format tests - type field format (Slack API format)
########################################################

@test "parse_payload:: supports type field format for rich-text block" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				blocks: [
					{
						type: "rich-text",
						elements: [
							{
								type: "rich_text_section",
								elements: [
									{
										type: "text",
										text: "Hello from type field format"
									}
								]
							}
						]
					}
				]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]

	local payload_output
	payload_output=$(parse_payload "$TEST_PAYLOAD_FILE")
	# Verify the block was created correctly
	echo "$payload_output" | jq -e '.blocks[0].type == "rich_text"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].elements[0].type == "rich_text_section"' >/dev/null
}

@test "parse_payload:: supports type field format for section block" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				blocks: [
					{
						type: "section",
						text: {
							type: "plain_text",
							text: "Section block with type field"
						}
					}
				]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]

	local payload_output
	payload_output=$(parse_payload "$TEST_PAYLOAD_FILE")
	echo "$payload_output" | jq -e '.blocks[0].type == "section"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].text.text == "Section block with type field"' >/dev/null
}

@test "parse_payload:: supports type field format with color" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				blocks: [
					{
						type: "rich-text",
						color: "danger",
						elements: [
							{
								type: "rich_text_section",
								elements: [
									{
										type: "text",
										text: "Colored rich text block"
									}
								]
							}
						]
					}
				]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]

	local payload_output
	payload_output=$(parse_payload "$TEST_PAYLOAD_FILE")
	# Colored blocks should be in attachments
	echo "$payload_output" | jq -e '.attachments | length == 1' >/dev/null
	echo "$payload_output" | jq -e '.attachments[0].color == "#F44336"' >/dev/null
	echo "$payload_output" | jq -e '.attachments[0].blocks[0].type == "rich_text"' >/dev/null
}

@test "parse_payload:: supports mixing type field format and key-based format" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				blocks: [
					{
						type: "rich-text",
						elements: [
							{
								type: "rich_text_section",
								elements: [
									{
										type: "text",
										text: "First block with type field"
									}
								]
							}
						]
					},
					{
						"rich-text": {
							elements: [
								{
									type: "rich_text_section",
									elements: [
										{
											type: "text",
											text: "Second block with key format"
										}
									]
								}
							]
						}
					}
				]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]

	local payload_output
	payload_output=$(parse_payload "$TEST_PAYLOAD_FILE")
	# Both blocks should be created
	echo "$payload_output" | jq -e '.blocks | length == 2' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].type == "rich_text"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[1].type == "rich_text"' >/dev/null
}

@test "parse_payload:: type field format works with header block" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				blocks: [
					{
						type: "header",
						text: {
							type: "plain_text",
							text: "Header with type field"
						}
					}
				]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]

	local payload_output
	payload_output=$(parse_payload "$TEST_PAYLOAD_FILE")
	echo "$payload_output" | jq -e '.blocks[0].type == "header"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].text.text == "Header with type field"' >/dev/null
}

@test "parse_payload:: type field format works with context block" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				blocks: [
					{
						type: "context",
						elements: [
							{
								type: "plain_text",
								text: "Context block with type field"
							}
						]
					}
				]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]

	local payload_output
	payload_output=$(parse_payload "$TEST_PAYLOAD_FILE")
	echo "$payload_output" | jq -e '.blocks[0].type == "context"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].elements[0].text == "Context block with type field"' >/dev/null
}

@test "parse_payload:: type field format preserves block_id" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				blocks: [
					{
						type: "rich-text",
						block_id: "test-block-id",
						elements: [
							{
								type: "rich_text_section",
								elements: [
									{
										type: "text",
										text: "Block with ID"
									}
								]
							}
						]
					}
				]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]

	local payload_output
	payload_output=$(parse_payload "$TEST_PAYLOAD_FILE")
	echo "$payload_output" | jq -e '.blocks[0].block_id == "test-block-id"' >/dev/null
}

@test "parse_payload:: type field format works with divider block" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				blocks: [
					{
						type: "divider",
						block_id: "divider-block-id"
					}
				]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]

	local payload_output
	payload_output=$(parse_payload "$TEST_PAYLOAD_FILE")
	echo "$payload_output" | jq -e '.blocks[0].type == "divider"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].block_id == "divider-block-id"' >/dev/null
}

@test "parse_payload:: type field format works with markdown block" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				blocks: [
					{
						type: "markdown",
						text: "**Markdown** block with *type* field format"
					}
				]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]

	local payload_output
	payload_output=$(parse_payload "$TEST_PAYLOAD_FILE")
	# Markdown is a valid Slack block type (see https://docs.slack.dev/reference/block-kit/blocks/markdown-block)
	echo "$payload_output" | jq -e '.blocks[0].type == "markdown"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].text | contains("Markdown")' >/dev/null
}

@test "parse_payload:: type field format works with actions block" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				blocks: [
					{
						type: "actions",
						elements: [
							{
								type: "button",
								text: {
									type: "plain_text",
									text: "Click Me"
								},
								action_id: "test_action"
							}
						],
						block_id: "actions-block-id"
					}
				]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]

	local payload_output
	payload_output=$(parse_payload "$TEST_PAYLOAD_FILE")
	echo "$payload_output" | jq -e '.blocks[0].type == "actions"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].block_id == "actions-block-id"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].elements[0].type == "button"' >/dev/null
}

@test "parse_payload:: type field format works with image block" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				blocks: [
					{
						type: "image",
						image_url: "https://example.com/image.png",
						alt_text: "Test image",
						block_id: "image-block-id"
					}
				]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]

	local payload_output
	payload_output=$(parse_payload "$TEST_PAYLOAD_FILE")
	echo "$payload_output" | jq -e '.blocks[0].type == "image"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].image_url == "https://example.com/image.png"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].alt_text == "Test image"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].block_id == "image-block-id"' >/dev/null
}

@test "parse_payload:: type field format works with video block" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				blocks: [
					{
						type: "video",
						video_url: "https://www.youtube.com/watch?v=test123",
						thumbnail_url: "https://example.com/thumb.jpg",
						alt_text: "Test video",
						title: {
							type: "plain_text",
							text: "Test Video Title"
						},
						block_id: "video-block-id"
					}
				]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]

	local payload_output
	payload_output=$(parse_payload "$TEST_PAYLOAD_FILE")
	echo "$payload_output" | jq -e '.blocks[0].type == "video"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].video_url == "https://www.youtube.com/watch?v=test123"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].thumbnail_url == "https://example.com/thumb.jpg"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].title.text == "Test Video Title"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].block_id == "video-block-id"' >/dev/null
}

@test "parse_payload:: type field format works with table block" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				blocks: [
					{
						type: "table",
						rows: [
							[
								{
									type: "raw_text",
									text: "Header 1"
								},
								{
									type: "raw_text",
									text: "Header 2"
								}
							],
							[
								{
									type: "raw_text",
									text: "Row 1 Col 1"
								},
								{
									type: "raw_text",
									text: "Row 1 Col 2"
								}
							]
						]
					}
				]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]

	local payload_output
	payload_output=$(parse_payload "$TEST_PAYLOAD_FILE")
	# Table blocks go into attachments
	echo "$payload_output" | jq -e '.attachments | length == 1' >/dev/null
	# Table blocks are placed in attachments (table conversion to section blocks happens in table processing)
	echo "$payload_output" | jq -e '.attachments[0].blocks | length > 0' >/dev/null
	# Verify table structure is preserved
	echo "$payload_output" | jq -e '.attachments[0].blocks[0].rows != null' >/dev/null
}

@test "parse_payload:: key-based format still works (backward compatibility)" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				blocks: [
					{
						"rich-text": {
							elements: [
								{
									type: "rich_text_section",
									elements: [
										{
											type: "text",
											text: "Backward compatible format"
										}
									]
								}
							]
						}
					}
				]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]

	local payload_output
	payload_output=$(parse_payload "$TEST_PAYLOAD_FILE")
	echo "$payload_output" | jq -e '.blocks[0].type == "rich_text"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].elements[0].elements[0].text == "Backward compatible format"' >/dev/null
}

@test "parse_payload:: key-based format with color still works" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				blocks: [
					{
						"rich-text": {
							color: "success",
							elements: [
								{
									type: "rich_text_section",
									elements: [
										{
											type: "text",
											text: "Colored backward compatible format"
										}
									]
								}
							]
						}
					}
				]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]

	local payload_output
	payload_output=$(parse_payload "$TEST_PAYLOAD_FILE")
	# Colored blocks should be in attachments
	echo "$payload_output" | jq -e '.attachments | length == 1' >/dev/null
	echo "$payload_output" | jq -e '.attachments[0].color == "#4CAF50"' >/dev/null
}
