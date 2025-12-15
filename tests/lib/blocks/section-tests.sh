#!/usr/bin/env bats
#
# Test file for blocks/section.sh
#

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		echo "Failed to get git root" >&2
		exit 1
	fi

	SCRIPT="$GIT_ROOT/lib/blocks/section.sh"
	EXAMPLES_FILE="$GIT_ROOT/examples/section.yaml"

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

@test "create_text_section:: from example with markdown" {
	local section_json
	section_json=$(yq -o json -r '.jobs[] | select(.name == "section-with-mrkdwn-text-and-button-accessory") | .plan[0].params.blocks[0].section' "$EXAMPLES_FILE")
	local test_text
	test_text=$(echo "$section_json" | jq -r '.text')

	run create_text_section "$test_text"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "bold text"
	echo "$output" | grep -q "italicized text"
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

@test "create_section:: text section with markdown and button accessory from example" {
	TEST_INPUT=$(yq -o json -r '.jobs[] | select(.name == "section-with-mrkdwn-text-and-button-accessory") | .plan[0].params.blocks[0].section' "$EXAMPLES_FILE")

	run create_section <<<"$TEST_INPUT"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "section"' >/dev/null
	echo "$output" | jq -e '.text.type == "mrkdwn"' >/dev/null
	echo "$output" | jq -e '.text.text | contains("bold text")' >/dev/null
	echo "$output" | jq -e '.accessory.type == "button"' >/dev/null
	echo "$output" | jq -e '.block_id == "section_mrkdwn_text_001"' >/dev/null
}

@test "create_section:: fields section with block_id from example" {
	TEST_INPUT=$(yq -o json -r '.jobs[] | select(.name == "section-with-fields-array-and-block-id") | .plan[0].params.blocks[0].section' "$EXAMPLES_FILE")

	run create_section <<<"$TEST_INPUT"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "section"' >/dev/null
	echo "$output" | jq -e '.fields != null' >/dev/null
	echo "$output" | jq -e '.fields | length == 4' >/dev/null
	echo "$output" | jq -e '.block_id == "section_fields_001"' >/dev/null
}

@test "create_section:: text section with expand and image accessory from example" {
	TEST_INPUT=$(yq -o json -r '.jobs[] | select(.name == "section-with-plain-text-expand-and-image-accessory") | .plan[0].params.blocks[0].section' "$EXAMPLES_FILE")

	run create_section <<<"$TEST_INPUT"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "section"' >/dev/null
	echo "$output" | jq -e '.text.type == "plain_text"' >/dev/null
	echo "$output" | jq -e '.block_id == "section_expand_001"' >/dev/null
	echo "$output" | jq -e '.expand == true' >/dev/null
	echo "$output" | jq -e '.accessory.type == "image"' >/dev/null
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

@test "create_section:: text section with expand false" {
	local test_yaml
	test_yaml=$(
		cat <<EOF
type: text
text:
  type: plain_text
  text: "Test message"
expand: false
EOF
	)

	local test_input
	test_input=$(yq -o json <<<"$test_yaml")

	run create_section <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.expand == false' >/dev/null
}

@test "create_section:: text section with accessory image" {
	local test_yaml
	test_yaml=$(
		cat <<EOF
type: text
text:
  type: plain_text
  text: "Check out this image"
accessory:
  type: image
  image_url: "https://example.com/image.png"
  alt_text: "Example image"
EOF
	)

	local test_input
	test_input=$(yq -o json <<<"$test_yaml")

	run create_section <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.accessory.type == "image"' >/dev/null
	echo "$output" | jq -e '.accessory.image_url == "https://example.com/image.png"' >/dev/null
}
