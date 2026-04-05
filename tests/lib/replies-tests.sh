#!/usr/bin/env bats
#
# Test file for replies.sh
#

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		fail "Failed to get git root"
	fi

	SCRIPT="$GIT_ROOT/bin/send-to-slack.sh"
	if [[ ! -f "$SCRIPT" ]]; then
		fail "Script not found: $SCRIPT"
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
	cd "$GIT_ROOT" || return 1
	source "$GIT_ROOT/lib/slack/api.sh"
	source "$SCRIPT"
	source "$GIT_ROOT/lib/parse/payload.sh"
	source "$GIT_ROOT/lib/slack/replies.sh"

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
	[[ -n "${input_payload:-}" ]] && rm -f "$input_payload"
	if [[ -n "${_SLACK_WORKSPACE:-}" ]] && [[ -d "$_SLACK_WORKSPACE" ]]; then
		rm -rf "$_SLACK_WORKSPACE"
	fi
	return 0
}

########################################################
# Mocks
########################################################
mock_curl_success() {
	curl() {
		echo '{"ok": true, "channel": "C123", "ts": "1234567890.123456"}'
		echo '200'
		return 0
	}

	export -f curl
}

########################################################
# send_thread_replies
########################################################

@test "send_thread_replies:: returns 1 when input_payload_file is missing" {
	local parsed_payload
	parsed_payload=$(jq -n '{
		channel: "#test",
		blocks: [],
		thread_replies: [
			{
				blocks: [
					{
						type: "section",
						text: { type: "plain_text", text: "Reply 1" }
					}
				]
			}
		]
	}')

	local outfile
	outfile=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.replies-missing-input.XXXXXX")
	set +e
	send_thread_replies "/nonexistent/payload.json" "1234567890.123456" "$parsed_payload" >"$outfile" 2>&1
	local status=$?
	set -e

	[[ "$status" -eq 1 ]]
	grep -q "input_payload_file is missing or not readable" "$outfile"
	rm -f "$outfile"
}

@test "send_thread_replies:: skips when thread_replies is absent" {
	local parsed_payload
	parsed_payload='{"channel":"#test","blocks":[]}'

	local input_file
	input_file=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.thread-replies.XXXXXX")
	echo '{"source":{"slack_bot_user_oauth_token":"test-token"}}' >"$input_file"

	if ! send_thread_replies "$input_file" "1234567890.123456" "$parsed_payload"; then
		return 1
	fi
	rm -f "$input_file"
}

@test "send_thread_replies:: skips when thread_replies is empty array" {
	local parsed_payload
	parsed_payload='{"channel":"#test","blocks":[],"thread_replies":[]}'

	local input_file
	input_file=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.thread-replies.XXXXXX")
	echo '{"source":{"slack_bot_user_oauth_token":"test-token"}}' >"$input_file"

	if ! send_thread_replies "$input_file" "1234567890.123456" "$parsed_payload"; then
		return 1
	fi
	rm -f "$input_file"
}

@test "send_thread_replies:: skips when thread_ts is not set" {
	local parsed_payload
	parsed_payload=$(jq -n '{
		channel: "#test",
		blocks: [],
		thread_replies: [
			{
				blocks: [
					{
						type: "section",
						text: { type: "plain_text", text: "Reply 1" }
					}
				]
			}
		]
	}')

	local input_file
	input_file=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.thread-replies.XXXXXX")
	echo '{"source":{"slack_bot_user_oauth_token":"test-token"}}' >"$input_file"

	local outfile
	outfile=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.replies-out.XXXXXX")
	send_thread_replies "$input_file" "" "$parsed_payload" >"$outfile" 2>&1
	local status=$?
	rm -f "$input_file"

	[[ "$status" -eq 0 ]]
	grep -q "thread_ts is not set, skipping replies" "$outfile"
	rm -f "$outfile"
}

@test "send_thread_replies:: sends each reply with correct thread_ts" {
	SEND_NOTIFICATION_CALL_COUNT=0
	export SEND_NOTIFICATION_CALL_COUNT

	send_notification() {
		local payload="$1"
		SEND_NOTIFICATION_CALL_COUNT=$((SEND_NOTIFICATION_CALL_COUNT + 1))
		local ts
		ts=$(echo "$payload" | jq -r '.thread_ts // empty')
		echo "send_notification::thread_ts=${ts}" >&2
		return 0
	}
	export -f send_notification

	local parsed_payload
	parsed_payload=$(jq -n '{
		channel: "#test",
		blocks: [],
		thread_replies: [
			{
				blocks: [
					{
						section: {
							type: "text",
							text: { type: "plain_text", text: "Reply 1" }
						}
					}
				]
			},
			{
				blocks: [
					{
						section: {
							type: "text",
							text: { type: "plain_text", text: "Reply 2" }
						}
					}
				]
			}
		]
	}')

	local input_file
	input_file=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.thread-replies.XXXXXX")
	jq -n \
		--arg token "$SLACK_BOT_USER_OAUTH_TOKEN" \
		'{source: {slack_bot_user_oauth_token: $token}}' >"$input_file"

	DRY_RUN="false"
	export DRY_RUN

	local outfile
	outfile=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.replies-out.XXXXXX")
	send_thread_replies "$input_file" "1234567890.654321" "$parsed_payload" >"$outfile" 2>&1
	local status=$?
	rm -f "$input_file"

	[[ "$status" -eq 0 ]]
	[[ "$SEND_NOTIFICATION_CALL_COUNT" -eq 2 ]]
	grep -q "reply 1 of 2 sent" "$outfile"
	grep -q "reply 2 of 2 sent" "$outfile"
	rm -f "$outfile"
}

@test "send_thread_replies:: inherits bot identity from parent params" {
	SEND_NOTIFICATION_CALL_COUNT=0
	export SEND_NOTIFICATION_CALL_COUNT
	FIRST_REPLY_PAYLOAD=""
	export FIRST_REPLY_PAYLOAD

	send_notification() {
		SEND_NOTIFICATION_CALL_COUNT=$((SEND_NOTIFICATION_CALL_COUNT + 1))
		if [[ "$SEND_NOTIFICATION_CALL_COUNT" -eq 1 ]]; then
			FIRST_REPLY_PAYLOAD="$1"
		fi
		return 0
	}
	export -f send_notification

	local parsed_payload
	parsed_payload=$(jq -n '{
		channel: "#test",
		blocks: [],
		thread_replies: [
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
	}')

	local input_file
	input_file=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.thread-replies-id.XXXXXX")
	jq -n \
		--arg token "$SLACK_BOT_USER_OAUTH_TOKEN" \
		'{
			source: {slack_bot_user_oauth_token: $token},
			params: {
				username: "Deploy Bot",
				icon_emoji: ":ship:",
				icon_url: "https://example.com/icon.png"
			}
		}' >"$input_file"

	DRY_RUN="false"
	export DRY_RUN

	local outfile
	outfile=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.replies-id-out.XXXXXX")
	send_thread_replies "$input_file" "1234567890.654321" "$parsed_payload" >"$outfile" 2>&1
	local status=$?
	rm -f "$input_file"

	[[ "$status" -eq 0 ]]
	echo "$FIRST_REPLY_PAYLOAD" | jq -e '.username == "Deploy Bot"' >/dev/null
	echo "$FIRST_REPLY_PAYLOAD" | jq -e '.icon_emoji == ":ship:"' >/dev/null
	echo "$FIRST_REPLY_PAYLOAD" | jq -e '.icon_url == "https://example.com/icon.png"' >/dev/null
	rm -f "$outfile"
}

@test "send_thread_replies:: continues and returns 0 when parse_payload fails" {
	parse_payload() {
		echo "parse_payload:: parse error" >&2
		return 1
	}
	export -f parse_payload

	local parsed_payload
	parsed_payload=$(jq -n '{
		channel: "#test",
		blocks: [],
		thread_replies: [
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
	}')

	local input_file
	input_file=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.thread-replies.XXXXXX")
	echo '{"source":{"slack_bot_user_oauth_token":"test-token"}}' >"$input_file"

	local outfile
	outfile=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.replies-out.XXXXXX")
	send_thread_replies "$input_file" "1234567890.123456" "$parsed_payload" >"$outfile" 2>&1
	local status=$?
	rm -f "$input_file"

	[[ "$status" -eq 0 ]]
	grep -q "warning: reply 1 failed to parse, continuing" "$outfile"
	rm -f "$outfile"
}

@test "send_thread_replies:: continues and returns 0 when send_notification fails" {
	send_notification() {
		echo "send_notification:: error" >&2
		return 1
	}
	export -f send_notification

	local parsed_payload
	parsed_payload=$(jq -n '{
		channel: "#test",
		blocks: [],
		thread_replies: [
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
	}')

	local input_file
	input_file=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.thread-replies.XXXXXX")
	jq -n \
		--arg token "$SLACK_BOT_USER_OAUTH_TOKEN" \
		'{source: {slack_bot_user_oauth_token: $token}}' >"$input_file"

	DRY_RUN="false"
	export DRY_RUN

	local outfile
	outfile=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.replies-out.XXXXXX")
	send_thread_replies "$input_file" "1234567890.123456" "$parsed_payload" >"$outfile" 2>&1
	local status=$?
	rm -f "$input_file"

	[[ "$status" -eq 0 ]]
	grep -q "warning: reply 1 failed to send, continuing" "$outfile"
	rm -f "$outfile"
}

@test "main:: thread.replies without explicit thread_ts uses RESPONSE ts" {
	local test_payload
	test_payload=$(jq -n \
		--arg token "$SLACK_BOT_USER_OAUTH_TOKEN" \
		--arg channel "$CHANNEL" \
		'{
			source: {
				slack_bot_user_oauth_token: $token
			},
			params: {
				channel: $channel,
				dry_run: false,
				blocks: [
					{
						section: {
							type: "text",
							text: { type: "plain_text", text: "Parent block" }
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
						},
						{
							blocks: [
								{
									section: {
										type: "text",
										text: { type: "plain_text", text: "Reply 2" }
									}
								}
							]
						}
					]
				}
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	mock_curl_success

	DRY_RUN="false"
	export DRY_RUN

	run "$SCRIPT" <"$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "send_thread_replies:: sending 2 thread reply(s)"
	echo "$output" | grep -q "reply 1 of 2 sent"
	echo "$output" | grep -q "reply 2 of 2 sent"
	echo "$output" | grep -q "main:: finished running send-to-slack.sh successfully"
}

@test "main:: thread.replies with thread_ts sends N+1 messages" {
	local test_payload
	test_payload=$(jq -n \
		--arg token "$SLACK_BOT_USER_OAUTH_TOKEN" \
		--arg channel "$CHANNEL" \
		'{
			source: {
				slack_bot_user_oauth_token: $token
			},
			params: {
				channel: $channel,
				dry_run: false,
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

	mock_curl_success

	DRY_RUN="false"
	export DRY_RUN

	run "$SCRIPT" <"$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "send_thread_replies:: sending 1 thread reply(s)"
	echo "$output" | grep -q "reply 1 of 1 sent"
	echo "$output" | grep -q "main:: finished running send-to-slack.sh successfully"
}
