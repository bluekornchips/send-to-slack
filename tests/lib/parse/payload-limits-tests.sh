#!/usr/bin/env bats
#
# parse_payload block, attachment, and text limit tests.
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
# Block/attachment count limit tests
########################################################

mock_create_block() {
	create_block() {
		echo '{"type":"section","text":{"type":"plain_text","text":"mock block"}}' >"$CREATE_BLOCK_OUTPUT_FILE"
		return 0
	}
	export -f create_block
}

@test "parse_payload:: block count exceeds 50 blocks limit" {
	mock_create_block

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
	mock_create_block

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
	mock_create_block

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
	mock_create_block

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
	mock_create_block

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
