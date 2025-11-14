#!/usr/bin/env bats
#
# Test file for blocks/section.sh
#

SMOKE_TEST=${SMOKE_TEST:-false}

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		echo "Failed to get git root" >&2
		exit 1
	fi

	SCRIPT="$GIT_ROOT/bin/blocks/section.sh"
	EXAMPLES_FILE="$GIT_ROOT/examples/section.yaml"

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
	smoke_test_teardown
	return 0
}

########################################################
# Mocks
########################################################

mock_create_text_section() {
	#shellcheck disable=SC2329
	create_text_section() {
		return 0
	}
	export -f create_text_section
}

mock_create_fields_section() {
	#shellcheck disable=SC2329
	create_fields_section() {
		echo '[{"type":"plain_text","text":"Field 1"},{"type":"plain_text","text":"Field 2"}]'
		return 0
	}
	export -f create_fields_section
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
	# Create proper Slack message structure with the section block in blocks array
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
# create_text_section
########################################################

@test "create_text_section:: handles no input" {
	run create_text_section ""
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "text_json is required"
}

@test "create_text_section:: handles invalid JSON" {
	run create_text_section "invalid json"
	[[ "$status" -eq 1 ]]
}

@test "create_text_section:: plain text" {
	local test_yaml
	test_yaml=$(
		cat <<EOF
type: plain_text
text: "Hello, world!"
EOF
	)
	local test_input
	test_input=$(yq -o json <<<"$test_yaml")

	run create_text_section "$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Hello, world!"
}

@test "create_text_section:: from example" {
	local section_json
	section_json=$(yq -o json -r '.jobs[] | select(.name == "section-plain-text") | .plan[0].params.blocks[0].section' "$EXAMPLES_FILE")
	local test_text
	test_text=$(echo "$section_json" | jq -r '.text')

	run create_text_section "$test_text"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Hello, world!"
	echo "$output" | grep -q "plain text section"
}

@test "create_text_section:: mrkdwn" {
	local test_yaml
	test_yaml=$(
		cat <<EOF
type: mrkdwn
text: "Hello, world!"
EOF
	)

	local test_input
	test_input=$(yq -o json <<<"$test_yaml")

	run create_text_section "$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Hello, world!"
}

@test "create_text_section:: invalid type" {
	local test_yaml
	test_yaml=$(
		cat <<EOF
type: invalid
text: "Hello, world!"
EOF
	)

	local test_input
	test_input=$(yq -o json <<<"$test_yaml")

	run create_text_section "$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "text type must be one of: plain_text mrkdwn"
}

@test "create_text_section:: text too long" {
	# Generate a string of 3001 characters
	local text
	text=$(printf 'x%.0s' {1..3001})
	local test_yaml
	test_yaml=$(
		cat <<EOF
type: plain_text
text: "$text"
EOF
	)

	local test_input
	test_input=$(yq -o json <<<"$test_yaml")

	run create_text_section "$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "text length must be less than 3000"
}

########################################################
# create_section
########################################################
@test "create_section:: handles no input" {
	run create_section <<<''

	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "input is required"
}

@test "create_section:: handles invalid JSON" {
	run create_section <<<'invalid json'

	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "input must be valid JSON"
}

@test "create_section:: invalid section type" {
	TEST_YAML=$(
		cat <<EOF
type: invalid
EOF
	)

	TEST_INPUT=$(yq -o json <<<"$TEST_YAML")

	run create_section <<<"$TEST_INPUT"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "section type must be one of: text fields"
}

@test "create_section:: text section" {
	mock_create_text_section

	TEST_YAML=$(
		cat <<EOF
type: text
text:
  type: plain_text
  text: "Hello, world!"
EOF
	)

	TEST_INPUT=$(yq -o json <<<"$TEST_YAML")

	run create_section <<<"$TEST_INPUT"
	[[ "$status" -eq 0 ]]
}

@test "create_section:: text section from example" {
	TEST_INPUT=$(yq -o json -r '.jobs[] | select(.name == "section-plain-text") | .plan[0].params.blocks[0].section' "$EXAMPLES_FILE")

	run create_section <<<"$TEST_INPUT"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "section"' >/dev/null
	send_request_to_slack "$output"
}

@test "create_section:: mrkdwn section from example" {
	TEST_INPUT=$(yq -o json -r '.jobs[] | select(.name == "section-mrkdwn") | .plan[0].params.blocks[0].section' "$EXAMPLES_FILE")

	run create_section <<<"$TEST_INPUT"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "section"' >/dev/null
	echo "$output" | jq -e '.text.type == "mrkdwn"' >/dev/null
	send_request_to_slack "$output"
}

@test "create_fields_section:: handles no input" {
	run create_fields_section ""
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "fields_json is required"
}

@test "create_fields_section:: handles invalid JSON" {
	run create_fields_section "invalid json"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "fields_json must be valid JSON"
}

@test "create_fields_section:: handles empty array" {
	run create_fields_section "[]"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "fields array must not be empty"
}

@test "create_fields_section:: handles non-array input" {
	run create_fields_section '{"type":"plain_text","text":"Test"}'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "fields must be an array"
}

@test "create_fields_section:: validates field text length" {
	local long_text
	long_text=$(printf "a%.0s" {1..2001})
	local fields_json
	fields_json=$(jq -n --arg text "$long_text" '[{type: "plain_text", text: $text}]')

	run create_fields_section "$fields_json"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "text length must be less than 2000"
}

@test "create_fields_section:: validates max fields count" {
	local many_fields
	many_fields=$(jq -n '[range(11) | {type: "plain_text", text: "Field"}]')

	run create_fields_section "$many_fields"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "fields array cannot exceed 10 items"
}

@test "create_fields_section:: validates each field" {
	local invalid_fields
	invalid_fields=$(jq -n '[{type: "invalid", text: "Test"}]')

	run create_fields_section "$invalid_fields"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "field at index 0"
}

@test "create_fields_section:: creates valid fields array" {
	local fields_json
	fields_json=$(jq -n '[
		{type: "plain_text", text: "Field 1"},
		{type: "mrkdwn", text: "*Field 2*"}
	]')

	run create_fields_section "$fields_json"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e 'type == "array"' >/dev/null
	echo "$output" | jq -e 'length == 2' >/dev/null
	echo "$output" | jq -e '.[0].type == "plain_text"' >/dev/null
	echo "$output" | jq -e '.[1].type == "mrkdwn"' >/dev/null
}

@test "create_section:: fields section" {
	local test_yaml
	test_yaml=$(
		cat <<EOF
type: fields
fields:
  - type: plain_text
    text: "Hello, world!"
  - type: mrkdwn
    text: "*Bold text*"
EOF
	)

	local test_input
	test_input=$(yq -o json <<<"$test_yaml")

	run create_section <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "section"' >/dev/null
	echo "$output" | jq -e '.fields != null' >/dev/null
	echo "$output" | jq -e '.fields | length == 2' >/dev/null
	send_request_to_slack "$output"
}

@test "create_section:: fields section with block_id" {
	local test_yaml
	test_yaml=$(
		cat <<EOF
type: fields
fields:
  - type: plain_text
    text: "Field 1"
block_id: "test_block"
EOF
	)

	local test_input
	test_input=$(yq -o json <<<"$test_yaml")

	run create_section <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.block_id == "test_block"' >/dev/null
}

@test "create_section:: rejects both text and fields" {
	local test_yaml
	test_yaml=$(
		cat <<EOF
type: fields
text:
  type: plain_text
  text: "Text"
fields:
  - type: plain_text
    text: "Field"
EOF
	)

	local test_input
	test_input=$(yq -o json <<<"$test_yaml")

	run create_section <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "section cannot have both text and fields"
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

@test "smoke test, section block" {
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "section-plain-text") | .plan[0].params.blocks' "$EXAMPLES_FILE")

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

@test "smoke test, section block with fields" {
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "section-fields") | .plan[0].params.blocks' "$EXAMPLES_FILE")

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
