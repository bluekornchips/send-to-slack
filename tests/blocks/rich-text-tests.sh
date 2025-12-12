#!/usr/bin/env bats
#
# Test file for blocks/rich_text.sh
#

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

	export GIT_ROOT
	export SCRIPT
	export EXAMPLES_FILE

}

setup() {
	source "$SCRIPT"

	SEND_TO_SLACK_ROOT="$GIT_ROOT"

	export SEND_TO_SLACK_ROOT

	return 0
}

teardown() {
	[[ -n "$mock_script" ]] && rm -f "$mock_script"
	[[ -n "$stderr_file" ]] && rm -f "$stderr_file"
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
	local mock_script
	mock_script=$(mktemp rich-text-tests.mock_file_upload.XXXXXX)
	cat >"$mock_script" <<'EOF'
#!/bin/bash
echo '{"type": "section", "text": {"type": "mrkdwn", "text": "<http://example.com/file.txt|oversized-rich-text.txt>"}}'
EOF
	chmod +x "$mock_script"

	# Override the file upload script path
	local original_upload_script="$UPLOAD_FILE_SCRIPT"
	UPLOAD_FILE_SCRIPT="$mock_script"

	local json_output
	local stderr_file
	stderr_file=$(mktemp rich-text-tests.stderr.XXXXXX)
	json_output=$(create_rich_text <<<"$block_value" 2>"$stderr_file")
	local status=$?

	# Restore original
	UPLOAD_FILE_SCRIPT="$original_upload_script"
	rm -f "$mock_script" "$stderr_file"

	[[ "$status" -eq 0 ]]
	echo "$json_output" | jq -e '.type == "section"' >/dev/null
	echo "$json_output" | jq -e '.text.type == "mrkdwn"' >/dev/null
}
