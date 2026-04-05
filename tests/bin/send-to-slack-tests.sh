#!/usr/bin/env bats
#
# Test file for send-to-slack.sh
#

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		fail "Failed to get git root"
	fi

	SCRIPT="$GIT_ROOT/bin/send-to-slack.sh"
	if [[ ! -f "$SCRIPT" ]]; then
		fail "Script not found: ${SCRIPT}"
	fi

	if [[ -n "$SLACK_BOT_USER_OAUTH_TOKEN" ]]; then
		REAL_TOKEN="$SLACK_BOT_USER_OAUTH_TOKEN"
		export REAL_TOKEN
	fi

	export GIT_ROOT
	export SCRIPT
	export REAL_TOKEN

	return 0
}

setup() {
	source "$GIT_ROOT/lib/slack/api.sh"
	source "$GIT_ROOT/lib/metadata.sh"
	source "$GIT_ROOT/lib/health-check.sh"
	source "$SCRIPT"

	# Source lib/parse/payload.sh for parse_payload and process_blocks
	source "$GIT_ROOT/lib/parse/payload.sh"

	SLACK_BOT_USER_OAUTH_TOKEN="test-token"
	CHANNEL="#test"
	MESSAGE="test message"
	DRY_RUN="true"
	SHOW_METADATA="true"
	SHOW_PAYLOAD="true"
	BLOCKS="$(jq -n '[
		{
			"type": "section",
			"text": {
				"type": "plain_text",
				"text": "test message"
			}
		}
	]')"

	TEST_PAYLOAD_FILE=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.test-payload.XXXXXX")

	_SLACK_WORKSPACE=$(mktemp -d "${BATS_TEST_TMPDIR}/send-to-slack-tests.workspace.XXXXXX")

	export SLACK_BOT_USER_OAUTH_TOKEN
	export CHANNEL
	export MESSAGE
	export DRY_RUN
	export SHOW_METADATA
	export SHOW_PAYLOAD
	export TEST_PAYLOAD_FILE
	export _SLACK_WORKSPACE

	return 0
}

teardown() {
	rm -f "${TEST_PAYLOAD_FILE}"
	[[ -n "$input_payload" ]] && rm -f "$input_payload"
	[[ -n "$attempt_file" ]] && rm -f "$attempt_file"
	[[ -n "$unreadable_file" ]] && rm -f "$unreadable_file"
	[[ -n "$empty_file" ]] && rm -f "$empty_file"

	return 0
}

########################################################
# Helpers
########################################################

create_test_payload() {
	local blocks_config='[{"rich-text": {"elements": [{"type": "rich_text_section", "elements": [{"type": "text", "text": "test message"}]}]}}]'

	jq -n \
		--arg token "$SLACK_BOT_USER_OAUTH_TOKEN" \
		--arg channel "$CHANNEL" \
		--arg dry_run "$DRY_RUN" \
		--argjson blocks "$blocks_config" \
		'{
			source: {
				slack_bot_user_oauth_token: $token
			},
			params: {
				channel: $channel,
				dry_run: $dry_run,
				blocks: $blocks
			}
		}' >"$TEST_PAYLOAD_FILE"
}

########################################################
# version and health_check
########################################################

@test "version:: --version prints version and exits" {
	run "$SCRIPT" --version
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "^send-to-slack, (https://github.com/"
	echo "$output" | grep -q "^version: "
	echo "$output" | grep -q "^commit: "
	echo "$output" | grep -v -q "main::"
}

@test "version:: -v prints version and exits" {
	run "$SCRIPT" -v
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "^send-to-slack, (https://github.com/"
	echo "$output" | grep -q "^version: "
	echo "$output" | grep -q "^commit: "
	echo "$output" | grep -v -q "main::"
}

@test "health_check:: passes when dependencies are available" {
	unset SLACK_BOT_USER_OAUTH_TOKEN
	run health_check
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "jq found"
	echo "$output" | grep -q "curl found"
	echo "$output" | grep -q "Health check passed"
}

@test "health_check:: skips API check when token not set" {
	unset SLACK_BOT_USER_OAUTH_TOKEN
	run health_check
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "SLACK_BOT_USER_OAUTH_TOKEN not set, skipping API connectivity check"
}

@test "health_check:: tests API connectivity when token is set" {
	SLACK_BOT_USER_OAUTH_TOKEN="test-token"
	export SLACK_BOT_USER_OAUTH_TOKEN

	run health_check
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Testing Slack API connectivity"
}

@test "health_check:: --health-check flag works" {
	unset SLACK_BOT_USER_OAUTH_TOKEN
	run "$SCRIPT" --health-check
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "health_check"
}

########################################################
# main: debug and delivery
########################################################

@test "main:: params.debug=true overrides SHOW_METADATA to true" {
	SHOW_METADATA="false"
	SHOW_PAYLOAD="false"
	export SHOW_METADATA
	export SHOW_PAYLOAD
	local test_payload
	test_payload=$(jq -n '{
		source: {
			slack_bot_user_oauth_token: "xoxb-test-token"
		},
		params: {
			channel: "test-channel",
			dry_run: true,
			debug: true,
			blocks: [{
				section: {
					type: "text",
					text: { type: "plain_text", text: "Test" }
				}
			}]
		}
	}')

	local input_file
	input_file=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.input.XXXXXX")
	echo "$test_payload" >"$input_file"

	# Run main function (it will check debug and override)
	run main --file "$input_file"
	[[ "$status" -eq 0 ]]

	# Verify SHOW_METADATA was overridden to true
	echo "$output" | grep -q '"name": "show_metadata"'
	echo "$output" | grep -q '"value": "true"'

	rm -f "$input_file"
}

@test "main:: params.debug=true overrides SHOW_PAYLOAD to true" {
	SHOW_METADATA="true"
	SHOW_PAYLOAD="false"
	export SHOW_METADATA
	export SHOW_PAYLOAD
	local test_payload
	test_payload=$(jq -n '{
		source: {
			slack_bot_user_oauth_token: "xoxb-test-token"
		},
		params: {
			channel: "test-channel",
			dry_run: true,
			debug: true,
			blocks: [{
				section: {
					type: "text",
					text: { type: "plain_text", text: "Test" }
				}
			}]
		}
	}')

	local input_file
	input_file=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.input.XXXXXX")
	echo "$test_payload" >"$input_file"

	# Run main function (it will check debug and override)
	run main --file "$input_file"
	[[ "$status" -eq 0 ]]

	# Verify SHOW_PAYLOAD was overridden to true
	echo "$output" | grep -q '"name": "show_payload"'
	echo "$output" | grep -q '"value": "true"'
	# Verify payload is included in metadata
	echo "$output" | grep -q '"name": "payload"'

	rm -f "$input_file"
}

@test "main:: params.debug=false does not override SHOW_METADATA or SHOW_PAYLOAD" {
	SHOW_METADATA="false"
	SHOW_PAYLOAD="false"
	export SHOW_METADATA
	export SHOW_PAYLOAD
	local test_payload
	test_payload=$(jq -n '{
		source: {
			slack_bot_user_oauth_token: "xoxb-test-token"
		},
		params: {
			channel: "test-channel",
			dry_run: true,
			debug: false,
			blocks: [{
				section: {
					type: "text",
					text: { type: "plain_text", text: "Test" }
				}
			}]
		}
	}')

	local input_file
	input_file=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.input.XXXXXX")
	echo "$test_payload" >"$input_file"

	# Run main function
	run main --file "$input_file"
	[[ "$status" -eq 0 ]]

	# Verify metadata is empty (no override)
	echo "$output" | grep -q '"metadata": \[\]'

	rm -f "$input_file"
}

@test "main:: params.debug=true emits verbose trace logs" {
	local test_payload
	test_payload=$(jq -n '{
		source: {
			slack_bot_user_oauth_token: "xoxb-test-token"
		},
		params: {
			channel: "test-channel",
			dry_run: true,
			debug: true,
			blocks: [{
				section: {
					type: "text",
					text: { type: "plain_text", text: "Test" }
				}
			}]
		}
	}')

	local input_file
	input_file=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.input.XXXXXX")
	echo "$test_payload" >"$input_file"

	run main --file "$input_file"
	[[ "$status" -eq 0 ]]

	# Required pre-step logs appear regardless
	echo "$output" | grep -q "process_input_to_file:: reading input into"
	echo "$output" | grep -q "main:: parsing payload"

	# Verbose logs appear when debug is true
	echo "$output" | grep -q "load_configuration::"
	echo "$output" | grep -q "process_blocks::"

	rm -f "$input_file"
}

@test "main:: params.debug=false suppresses verbose trace logs" {
	local test_payload
	test_payload=$(jq -n '{
		source: {
			slack_bot_user_oauth_token: "xoxb-test-token"
		},
		params: {
			channel: "test-channel",
			dry_run: true,
			debug: false,
			blocks: [{
				section: {
					type: "text",
					text: { type: "plain_text", text: "Test" }
				}
			}]
		}
	}')

	local input_file
	input_file=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.input.XXXXXX")
	echo "$test_payload" >"$input_file"

	run main --file "$input_file"
	[[ "$status" -eq 0 ]]

	# Required pre-step logs still appear
	echo "$output" | grep -q "process_input_to_file:: reading input into"
	echo "$output" | grep -q "main:: parsing payload"

	# Verbose logs do not appear when debug is false
	echo "$output" | grep -qv "parse_payload:: input payload (sanitized):"

	rm -f "$input_file"
}

@test "main:: webhook delivery skips thread replies and crosspost" {
	unset SLACK_BOT_USER_OAUTH_TOKEN
	unset CHANNEL

	curl() {
		echo "ok"
		echo "200"
		return 0
	}
	export -f curl

	local test_payload
	test_payload=$(jq -n '{
		source: {
			webhook_url: "https://hooks.slack.com/services/test"
		},
		params: {
			dry_run: false,
			blocks: [{
				section: {
					type: "text",
					text: { type: "plain_text", text: "Primary" }
				}
			}],
			thread: {
				replies: [{
					blocks: [{
						section: {
							type: "text",
							text: { type: "plain_text", text: "Reply" }
						}
					}]
				}]
			},
			crosspost: {
				channel: ["#side-channel"],
				blocks: [{
					section: {
						type: "text",
						text: { type: "plain_text", text: "Crosspost" }
					}
				}]
			}
		}
	}')

	local input_file
	input_file=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.input.XXXXXX")
	echo "$test_payload" >"$input_file"

	run main --file "$input_file"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "delivery method webhook does not support thread replies, skipping send_thread_replies"
	echo "$output" | grep -q "delivery method webhook does not support crosspost, skipping crosspost_notification"

	rm -f "$input_file"
}

@test "main:: skips thread_replies and crosspost for ephemeral messages" {
	local test_payload
	test_payload=$(jq -n '{
		source: {
			slack_bot_user_oauth_token: "xoxb-test-token"
		},
		params: {
			channel: "C123",
			dry_run: true,
			ephemeral_user: "U123",
			blocks: [{
				section: {
					type: "text",
					text: { type: "plain_text", text: "Primary" }
				}
			}],
			thread: {
				replies: [{
					blocks: [{
						section: {
							type: "text",
							text: { type: "plain_text", text: "Reply" }
						}
					}]
				}]
			},
			crosspost: {
				channel: ["#side-channel"],
				blocks: [{
					section: {
						type: "text",
						text: { type: "plain_text", text: "Crosspost" }
					}
				}]
			}
		}
	}')

	local input_file
	input_file=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.ephemeral-input.XXXXXX")
	echo "$test_payload" >"$input_file"

	run main --file "$input_file"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "chat.postEphemeral does not support thread replies or crosspost"
	# shellcheck disable=SC2154
	! echo "$output" | grep -q "send_thread_replies:: sending"

	rm -f "$input_file"
}

########################################################
# main: CLI input and validation
########################################################

@test "main:: accepts -file option with valid file" {
	create_test_payload

	run "$SCRIPT" -file "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "version"
	echo "$output" | grep -q "timestamp"
	echo "$output" | grep -q "main:: parsing payload"
}

@test "main:: accepts --file option with valid file" {
	create_test_payload

	run "$SCRIPT" --file "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "version"
	echo "$output" | grep -q "timestamp"
	echo "$output" | grep -q "main:: parsing payload"
}

@test "main:: fails when -file option is specified without file path" {

	run "$SCRIPT" -file
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "parse_main_args::"
	echo "$output" | grep -q "requires a file path argument"
}

@test "main:: fails when --file option is specified without file path" {

	run "$SCRIPT" --file
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "parse_main_args::"
	echo "$output" | grep -q "requires a file path argument"
}

@test "main:: fails when file does not exist" {
	local nonexistent_file
	nonexistent_file="/tmp/nonexistent-file-$(date +%s).json"

	run "$SCRIPT" -file "$nonexistent_file"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "process_input_to_file::"
	echo "$output" | grep -q "input file does not exist"
}

@test "main:: fails when file is empty" {
	local empty_file
	empty_file=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.empty.XXXXXX")
	touch "$empty_file"

	run "$SCRIPT" -file "$empty_file"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "process_input_to_file::"
	echo "$output" | grep -q "input file is empty"

	rm -f "$empty_file"
}

@test "main:: uses file and ignores stdin when both are provided" {
	create_test_payload

	local stdin_copy
	stdin_copy=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.payload-stdin.XXXXXX")
	trap 'rm -f "$stdin_copy"' RETURN
	cp "$TEST_PAYLOAD_FILE" "$stdin_copy"

	run "$SCRIPT" -file "$TEST_PAYLOAD_FILE" <"$stdin_copy"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "main:: finished running send-to-slack.sh successfully"
}

@test "main:: fails when no input is provided" {

	# When stdin is empty (/dev/null), script will try to read and detect empty input
	run "$SCRIPT" </dev/null
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "process_input_to_file::"
	echo "$output" | grep -q "no input received on stdin"
}

@test "main:: fails when -file option is specified multiple times" {
	create_test_payload

	run "$SCRIPT" -file "$TEST_PAYLOAD_FILE" -file "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "parse_main_args::"
	echo "$output" | grep -q "can only be specified once"
}

@test "main:: fails with unknown option" {

	run "$SCRIPT" --unknown-option
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "parse_main_args::"
	echo "$output" | grep -q "unknown option"
}

@test "main:: fails when both token and webhook are missing" {
	unset SLACK_BOT_USER_OAUTH_TOKEN

	local input_file
	input_file=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.missing-delivery.XXXXXX")
	jq -n '{
		source: {
		},
		params: {
			channel: "#test",
			blocks: [{
				section: {
					type: "text",
					text: { type: "plain_text", text: "Test" }
				}
			}]
		}
	}' >"$input_file"

	run "$SCRIPT" --file "$input_file"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "either source.slack_bot_user_oauth_token or source.webhook_url is required"

	rm -f "$input_file"
}

@test "main:: webhook mode does not require params.channel" {
	unset SLACK_BOT_USER_OAUTH_TOKEN
	unset CHANNEL

	curl() {
		echo "ok"
		echo "200"
		return 0
	}
	export -f curl

	local input_file
	input_file=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.webhook-no-channel.XXXXXX")
	jq -n '{
		source: {
			webhook_url: "https://hooks.slack.com/services/test"
		},
		params: {
			blocks: [{
				section: {
					type: "text",
					text: { type: "plain_text", text: "Test" }
				}
			}]
		}
	}' >"$input_file"

	run "$SCRIPT" --file "$input_file"
	[[ "$status" -eq 0 ]]

	rm -f "$input_file"
}

@test "main:: file input works same as stdin input" {
	create_test_payload

	# Test with stdin

	run "$SCRIPT" <"$TEST_PAYLOAD_FILE"
	local stdin_status="$status"
	local stdin_output="$output"

	# Test with file option

	run "$SCRIPT" -file "$TEST_PAYLOAD_FILE"
	local file_status="$status"
	local file_output="$output"

	# Both should succeed
	[[ "$stdin_status" -eq 0 ]]
	[[ "$file_status" -eq 0 ]]

	# Both should produce similar output (version and timestamp)
	echo "$stdin_output" | grep -q "version"
	echo "$stdin_output" | grep -q "timestamp"
	echo "$file_output" | grep -q "version"
	echo "$file_output" | grep -q "timestamp"
}
