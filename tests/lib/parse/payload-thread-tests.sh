#!/usr/bin/env bats
#
# parse_payload thread_ts and thread.replies tests.
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
# thread.replies
########################################################

@test "parse_payload:: thread.replies without blocks succeeds as no-op" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				thread: {
					replies: [
						{
							blocks: [
								{
									section: {
										type: "text",
										text: { type: "plain_text", text: "Reply 1" }
									}
								}
							]
						}
					]
				}
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
}

@test "parse_payload:: thread.replies not an array fails" {
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
						section: {
							type: "text",
							text: { type: "plain_text", text: "Parent" }
						}
					}
				],
				thread: {
					replies: "not-an-array"
				}
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "thread.replies must be an array"
}

@test "parse_payload:: thread.replies entry missing blocks key fails" {
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
						section: {
							type: "text",
							text: { type: "plain_text", text: "Parent" }
						}
					}
				],
				thread: {
					replies: [
						{ text: "no blocks key here" }
					]
				}
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "thread.replies\[0\].blocks is required and must be non-empty"
}

@test "parse_payload:: thread.replies entry with empty blocks fails" {
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
						section: {
							type: "text",
							text: { type: "plain_text", text: "Parent" }
						}
					}
				],
				thread: {
					replies: [
						{ blocks: [] }
					]
				}
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "thread.replies\[0\].blocks is required and must be non-empty"
}

@test "parse_payload:: thread.replies empty array is a no-op" {
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
						section: {
							type: "text",
							text: { type: "plain_text", text: "Parent" }
						}
					}
				],
				thread: {
					replies: []
				}
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	local payload_output
	if ! payload_output=$(parse_payload "$TEST_PAYLOAD_FILE"); then
		return 1
	fi
	echo "$payload_output" | jq -e 'has("thread_replies") == false' >/dev/null
}

@test "parse_payload:: thread.replies passes through to parsed output with thread_ts" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				thread_ts: "1234567890.123456",
				blocks: [
					{
						section: {
							type: "text",
							text: { type: "plain_text", text: "Message in thread" }
						}
					}
				],
				thread: {
					replies: [
						{
							blocks: [
								{
									section: {
										type: "text",
										text: { type: "plain_text", text: "Reply 1" }
									}
								}
							]
						}
					]
				}
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	local payload_output
	payload_output=$(parse_payload "$TEST_PAYLOAD_FILE")
	echo "$payload_output" | jq -e '.thread_replies | length == 1' >/dev/null
	echo "$payload_output" | jq -e '.thread_ts == "1234567890.123456"' >/dev/null
}

