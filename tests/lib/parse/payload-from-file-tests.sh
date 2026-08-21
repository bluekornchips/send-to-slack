#!/usr/bin/env bats
#
# parse_payload block-level from_file tests.
#

load "payload-test-helper.sh"

setup_file() {
	payload_tests_setup_file
}

setup() {
	payload_tests_setup
}

teardown() {
	payload_tests_teardown
}

########################################################
# Block-level from_file
########################################################

@test "parse_payload:: block from_file success" {
	local block_file
	block_file="$BLOCK_FIXTURES_DIR/blocks-from-file.json"

	local test_payload
	test_payload=$(jq -n \
		--arg file "$block_file" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: "test-channel",
				blocks: [{ from_file: $file }]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "process_blocks:: expanded block from file"

	local payload_output
	payload_output=$(parse_payload "$TEST_PAYLOAD_FILE")
	echo "$payload_output" | jq -e '.blocks[0].type == "section"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].text.text == "Blocks loaded from file"' >/dev/null
}

@test "parse_payload:: block from_file not found" {
	local test_payload
	test_payload=$(jq -n '{
		source: { slack_bot_user_oauth_token: "test-token" },
		params: {
			channel: "test-channel",
			blocks: [{ from_file: "/nonexistent/block.json" }]
		}
	}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "not found"
}

@test "parse_payload:: block from_file invalid json" {
	local block_file
	block_file=$(mktemp "${BATS_TEST_TMPDIR}/payload-tests.block-invalid.XXXXXX")
	trap 'rm -f "$block_file" 2>/dev/null || true' EXIT
	echo "invalid json" >"$block_file"

	local test_payload
	test_payload=$(jq -n --arg file "$block_file" '{
		source: { slack_bot_user_oauth_token: "test-token" },
		params: {
			channel: "test-channel",
			blocks: [{ from_file: $file }]
		}
	}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "block file contains invalid JSON"

	rm -f "$block_file"
	trap - EXIT
}

@test "parse_payload:: block from_file empty path fails" {
	local test_payload
	test_payload=$(jq -n '{
		source: { slack_bot_user_oauth_token: "test-token" },
		params: {
			channel: "test-channel",
			blocks: [{ from_file: "" }]
		}
	}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "block from_file path is empty"
}

@test "parse_payload:: block from_file path is directory fails" {
	local dir_path
	dir_path=$(mktemp -d "${BATS_TEST_TMPDIR}/payload-tests.block-dir.XXXXXX")
	trap 'rm -rf "$dir_path" 2>/dev/null || true' EXIT

	local test_payload
	test_payload=$(jq -n --arg dir "$dir_path" '{
		source: { slack_bot_user_oauth_token: "test-token" },
		params: {
			channel: "test-channel",
			blocks: [{ from_file: $dir }]
		}
	}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "path is a directory"

	rm -rf "$dir_path"
	trap - EXIT
}

@test "parse_payload:: block from_file resolves with SEND_TO_SLACK_PAYLOAD_BASE_DIR" {
	local base_dir
	base_dir=$(mktemp -d "${BATS_TEST_TMPDIR}/payload-tests.block-base.XXXXXX")
	trap 'rm -rf "$base_dir" 2>/dev/null || true' EXIT

	mkdir -p "${base_dir}/nested"
	cp "$BLOCK_FIXTURES_DIR/blocks-from-file.json" "${base_dir}/nested/blocks.json"
	jq '(.section.text.text) = "From base dir block"' "${base_dir}/nested/blocks.json" >"${base_dir}/nested/blocks.json.tmp"
	mv "${base_dir}/nested/blocks.json.tmp" "${base_dir}/nested/blocks.json"

	local test_payload
	test_payload=$(jq -n '{
		source: { slack_bot_user_oauth_token: "test-token" },
		params: {
			channel: "test-channel",
			blocks: [{ from_file: "nested/blocks.json" }]
		}
	}')
	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	SEND_TO_SLACK_PAYLOAD_BASE_DIR="$base_dir"
	export SEND_TO_SLACK_PAYLOAD_BASE_DIR
	run parse_payload "$TEST_PAYLOAD_FILE"
	unset SEND_TO_SLACK_PAYLOAD_BASE_DIR

	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "process_blocks:: expanded block from file"

	local payload_output
	SEND_TO_SLACK_PAYLOAD_BASE_DIR="$base_dir"
	export SEND_TO_SLACK_PAYLOAD_BASE_DIR
	payload_output=$(parse_payload "$TEST_PAYLOAD_FILE")
	unset SEND_TO_SLACK_PAYLOAD_BASE_DIR
	echo "$payload_output" | jq -e '.blocks[0].text.text == "From base dir block"' >/dev/null

	rm -rf "$base_dir"
	trap - EXIT
}

@test "parse_payload:: block from_file mixed with inline blocks" {
	local block_file
	block_file="$BLOCK_FIXTURES_DIR/blocks-from-file.json"

	local test_payload
	test_payload=$(jq -n \
		--arg file "$block_file" \
		'{
			source: { slack_bot_user_oauth_token: "test-token" },
			params: {
				channel: "test-channel",
				blocks: [
					{
						section: {
							type: "text",
							text: { type: "plain_text", text: "Inline first" }
						}
					},
					{ from_file: $file },
					{
						context: {
							elements: [{ type: "plain_text", text: "Inline last" }]
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
	echo "$payload_output" | jq -e '.blocks | length == 3' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].text.text == "Inline first"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[1].text.text == "Blocks loaded from file"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[2].type == "context"' >/dev/null
}

@test "parse_payload:: block from_file with array expands to multiple blocks" {
	local block_file
	# Use a file that contains an array of blocks to test array expansion
	block_file="$BLOCK_FIXTURES_DIR/blocks-from-file.json"

	# Create a test file with an array of blocks
	local array_file
	array_file=$(mktemp "${BATS_TEST_TMPDIR}/payload-tests.array-blocks.XXXXXX")
	trap 'rm -f "$array_file"' EXIT

	cat >"$array_file" <<'EOF'
[
  {
    "header": {
      "text": { "type": "plain_text", "text": "First Block from Array" }
    }
  },
  {
    "section": {
      "type": "text",
      "text": { "type": "plain_text", "text": "Second Block from Array" }
    }
  },
  {
    "divider": {}
  }
]
EOF

	local test_payload
	test_payload=$(jq -n \
		--arg file "$array_file" \
		'{
			source: { slack_bot_user_oauth_token: "test-token" },
			params: {
				channel: "test-channel",
				blocks: [{ from_file: $file }]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]

	local payload_output
	payload_output=$(parse_payload "$TEST_PAYLOAD_FILE")
	# Verify that the array was expanded into multiple blocks
	echo "$payload_output" | jq -e '.blocks | length == 3' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].type == "header"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[0].text.text == "First Block from Array"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[1].type == "section"' >/dev/null
	echo "$payload_output" | jq -e '.blocks[2].type == "divider"' >/dev/null

	rm -f "$array_file"
	trap - EXIT
}
