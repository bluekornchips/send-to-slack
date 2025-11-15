#!/usr/bin/env bats
#
# Test file for blocks/markdown.sh
#

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		echo "Failed to get git root" >&2
		exit 1
	fi

	SCRIPT="$GIT_ROOT/bin/blocks/markdown.sh"
	EXAMPLES_FILE="$GIT_ROOT/examples/markdown.yaml"

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
# create_markdown
########################################################

@test "create_markdown:: handles no input" {
	run create_markdown <<<''
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "input is required"
}

@test "create_markdown:: handles invalid JSON" {
	run create_markdown <<<'invalid json'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "input must be valid JSON"
}

@test "create_markdown:: missing text field" {
	local test_input
	test_input='{}'
	run create_markdown <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "text field is required"
}

@test "create_markdown:: empty text content" {
	local test_input
	test_input='{"text": ""}'
	run create_markdown <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "text field is required"
}

@test "create_markdown:: text too long" {
	local long_text
	long_text=$(printf 'x%.0s' {1..12001})
	local test_input
	test_input=$(jq -n --arg text "$long_text" '{text: $text}')
	run create_markdown <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "text must be 12000 characters or less"
}

@test "create_markdown:: basic markdown" {
	local test_input
	test_input='{"text": "**Lots of information here!!**"}'
	run create_markdown <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "markdown"' >/dev/null
	echo "$output" | jq -e '.text == "**Lots of information here!!**"' >/dev/null
}

@test "create_markdown:: markdown with formatting" {
	local test_input
	test_input='{"text": "*This text is italicized* and **this is bold**"}'
	run create_markdown <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "markdown"' >/dev/null
	echo "$output" | jq -e '.text | contains("italicized")' >/dev/null
	echo "$output" | jq -e '.text | contains("bold")' >/dev/null
}

@test "create_markdown:: maximum length text" {
	local max_text
	max_text=$(printf 'x%.0s' {1..12000})
	local test_input
	test_input=$(jq -n --arg text "$max_text" '{text: $text}')
	run create_markdown <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.text | length == 12000' >/dev/null
}

@test "create_markdown:: markdown with links" {
	local test_input
	test_input='{"text": "[my text](https://www.google.com)"}'
	run create_markdown <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "markdown"' >/dev/null
	echo "$output" | jq -e '.text | contains("google.com")' >/dev/null
}
