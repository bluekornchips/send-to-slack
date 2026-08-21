#!/usr/bin/env bats
#
# parse_payload type-field and key-based block format tests.
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
