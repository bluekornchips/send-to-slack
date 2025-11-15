#!/usr/bin/env bats
#
# Test file for blocks/image.sh
#

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		echo "Failed to get git root" >&2
		exit 1
	fi

	SCRIPT="$GIT_ROOT/bin/blocks/image.sh"
	EXAMPLES_FILE="$GIT_ROOT/examples/image.yaml"

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
# create_image
########################################################

@test "create_image:: handles no input" {
	run create_image <<<''
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "input is required"
}

@test "create_image:: handles invalid JSON" {
	run create_image <<<'invalid json'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "input must be valid JSON"
}

@test "create_image:: missing image_url and slack_file fields" {
	local test_input
	test_input='{"alt_text": "Test image"}'
	run create_image <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "either image_url or slack_file field is required"
}

@test "create_image:: missing alt_text field" {
	local test_input
	test_input='{"image_url": "https://example.com/image.png"}'
	run create_image <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "alt_text field is required"
}

@test "create_image:: empty image_url" {
	local test_input
	test_input='{"image_url": "", "alt_text": "Test image"}'
	run create_image <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "either image_url or slack_file field is required"
}

@test "create_image:: empty alt_text" {
	local test_input
	test_input='{"image_url": "https://example.com/image.png", "alt_text": ""}'
	run create_image <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "alt_text field is required"
}

@test "create_image:: both image_url and slack_file provided" {
	local test_input
	test_input='{"image_url": "https://example.com/image.png", "slack_file": {"url": "https://files.slack.com/files-pri/T0123456-F0123456/xyz.png"}, "alt_text": "Test image"}'
	run create_image <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "cannot have both image_url and slack_file"
}

@test "create_image:: alt_text too long" {
	local long_text
	long_text=$(printf 'x%.0s' {1..2001})
	local test_input
	test_input=$(jq -n \
		--arg image_url "https://example.com/image.png" \
		--arg alt_text "$long_text" \
		'{image_url: $image_url, alt_text: $alt_text}')
	run create_image <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "alt_text must be 2000 characters or less"
}

@test "create_image:: title text too long" {
	local long_text
	long_text=$(printf 'x%.0s' {1..2001})
	local test_input
	test_input=$(jq -n \
		--arg image_url "https://example.com/image.png" \
		--arg alt_text "Test image" \
		--arg title_text "$long_text" \
		'{image_url: $image_url, alt_text: $alt_text, title: {type: "plain_text", text: $title_text}}')
	run create_image <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "title text must be 2000 characters or less"
}

@test "create_image:: block_id too long" {
	local long_block_id
	long_block_id=$(printf 'x%.0s' {1..256})
	local test_input
	test_input=$(jq -n \
		--arg image_url "https://example.com/image.png" \
		--arg alt_text "Test image" \
		--arg block_id "$long_block_id" \
		'{image_url: $image_url, alt_text: $alt_text, block_id: $block_id}')
	run create_image <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "block_id must be 255 characters or less"
}

@test "create_image:: invalid title type" {
	local test_input
	test_input='{"image_url": "https://example.com/image.png", "alt_text": "Test image", "title": {"type": "mrkdwn", "text": "Test"}}'
	run create_image <<<"$test_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "title type must be plain_text"
}

@test "create_image:: basic image block" {
	local test_input
	test_input='{"image_url": "https://example.com/image.png", "alt_text": "Test image"}'
	run create_image <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "image"' >/dev/null
	echo "$output" | jq -e '.image_url == "https://example.com/image.png"' >/dev/null
	echo "$output" | jq -e '.alt_text == "Test image"' >/dev/null
}

@test "create_image:: with title" {
	local test_input
	test_input='{"image_url": "https://example.com/image.png", "alt_text": "Test image", "title": {"type": "plain_text", "text": "Image Title"}}'
	run create_image <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.title.type == "plain_text"' >/dev/null
	echo "$output" | jq -e '.title.text == "Image Title"' >/dev/null
}

@test "create_image:: with block_id" {
	local test_input
	test_input='{"image_url": "https://example.com/image.png", "alt_text": "Test image", "block_id": "image_123"}'
	run create_image <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.block_id == "image_123"' >/dev/null
}

@test "create_image:: with all fields" {
	local test_input
	test_input='{"image_url": "https://example.com/image.png", "alt_text": "Test image", "title": {"type": "plain_text", "text": "Image Title"}, "block_id": "image_123"}'
	run create_image <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "image"' >/dev/null
	echo "$output" | jq -e '.image_url' >/dev/null
	echo "$output" | jq -e '.alt_text' >/dev/null
	echo "$output" | jq -e '.title' >/dev/null
	echo "$output" | jq -e '.block_id' >/dev/null
}

@test "create_image:: maximum length alt_text" {
	local max_text
	max_text=$(printf 'x%.0s' {1..2000})
	local test_input
	test_input=$(jq -n \
		--arg image_url "https://example.com/image.png" \
		--arg alt_text "$max_text" \
		'{image_url: $image_url, alt_text: $alt_text}')
	run create_image <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.alt_text | length == 2000' >/dev/null
}

@test "create_image:: with image_url title and block_id from example" {
	local image_json
	image_json=$(yq -o json -r '.jobs[] | select(.name == "image-with-url-title-and-block-id") | .plan[0].params.blocks[0].image' "$EXAMPLES_FILE")

	run create_image <<<"$image_json"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "image"' >/dev/null
	echo "$output" | jq -e '.image_url == "https://sunflowersoftware.ca/wp-content/uploads/2023/05/cropped-sunflower.gif"' >/dev/null
	echo "$output" | jq -e '.alt_text == "Animated sunflower"' >/dev/null
	echo "$output" | jq -e '.title.type == "plain_text"' >/dev/null
	echo "$output" | jq -e '.title.text == "Please enjoy this sunflower animation"' >/dev/null
	echo "$output" | jq -e '.block_id == "image4"' >/dev/null
}

@test "create_image:: with slack_file url from example" {
	local image_json
	image_json=$(yq -o json -r '.jobs[] | select(.name == "image-with-slack-file-url") | .plan[0].params.blocks[0].image' "$EXAMPLES_FILE")

	run create_image <<<"$image_json"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "image"' >/dev/null
	echo "$output" | jq -e '.slack_file.url == "https://files.slack.com/files-pri/T0123456-F0123456/xyz.png"' >/dev/null
	echo "$output" | jq -e '.alt_text == "Animated sunflower"' >/dev/null
}

@test "create_image:: with slack_file id from example" {
	local image_json
	image_json=$(yq -o json -r '.jobs[] | select(.name == "image-with-slack-file-id") | .plan[0].params.blocks[0].image' "$EXAMPLES_FILE")

	run create_image <<<"$image_json"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.type == "image"' >/dev/null
	echo "$output" | jq -e '.slack_file.id == "F012345678"' >/dev/null
	echo "$output" | jq -e '.alt_text == "Animated sunflower"' >/dev/null
}
