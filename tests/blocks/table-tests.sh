#!/usr/bin/env bats
#
# Test file for blocks/table.sh
#

SMOKE_TEST=${SMOKE_TEST:-false}

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		echo "Failed to get git root" >&2
		exit 1
	fi

	SCRIPT="$GIT_ROOT/bin/blocks/table.sh"
	EXAMPLES_FILE="$GIT_ROOT/examples/table.yaml"
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
# create_table
########################################################

@test "create_table:: handles no input" {
	run create_table <<<''
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "input is required"
}

@test "create_table:: handles invalid JSON" {
	run create_table <<<'invalid json'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "input must be valid JSON"
}

@test "create_table:: missing elements" {
	run create_table <<<'{"block_id": "test_id"}'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "rows field is required"
}

@test "create_table:: with rows" {
	run create_table <<<'{"rows": [[{"type": "raw_text", "text": "Hello, world!"}]]}'
	[[ "$status" -eq 0 ]]
	echo "$output" | jq '.rows[0][0].text == "Hello, world!"' >/dev/null
}

@test "create_table:: with block_id" {
	run create_table <<<'{"block_id": "test_id", "rows": [[{"type": "raw_text", "text": "test"}]]}'
	[[ "$status" -eq 0 ]]
	echo "$output" | jq '.block_id == "test_id"' >/dev/null
}

@test "create_table:: with column_settings" {
	run create_table <<<'{"column_settings": [{"align": "left"}], "rows": [[{"type": "raw_text", "text": "test"}]]}'
	[[ "$status" -eq 0 ]]
	echo "$output" | jq '.column_settings[0].align == "left"' >/dev/null
}

@test "create_table:: rows not array" {
	run create_table <<<'{"rows": "not an array"}'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "rows must be an array"
}

@test "create_table:: row not array" {
	run create_table <<<'{"rows": ["not an array"]}'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "row 0 must be an array"
}

@test "create_table:: cell missing type" {
	run create_table <<<'{"rows": [[{"text": "test"}]]}'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "cell \[0,0\] must have a type field"
}

@test "create_table:: invalid cell type" {
	run create_table <<<'{"rows": [[{"type": "invalid", "text": "test"}]]}'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "cell \[0,0\] type must be one of"
}

@test "create_table:: invalid column alignment" {
	run create_table <<<'{"column_settings": [{"align": "invalid"}], "rows": [[{"type": "raw_text", "text": "test"}]]}'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "align must be one of"
}

@test "create_table:: invalid column is_wrapped type" {
	run create_table <<<'{"column_settings": [{"is_wrapped": "not boolean"}], "rows": [[{"type": "raw_text", "text": "test"}]]}'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "is_wrapped must be a boolean"
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
	#shellcheck disable=SC1090
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

@test "smoke test, basic" {
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

@test "smoke test, basic-colored" {
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "basic-colored") | .plan[0].params.blocks' "$EXAMPLES_FILE")

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

@test "smoke test, with-block-id" {
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "with-block-id") | .plan[0].params.blocks' "$EXAMPLES_FILE")

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

@test "smoke test, with-column-settings" {
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "with-column-settings") | .plan[0].params.blocks' "$EXAMPLES_FILE")

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

@test "smoke test, with-rich-text-cells" {
	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "with-rich-text-cells") | .plan[0].params.blocks' "$EXAMPLES_FILE")

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
