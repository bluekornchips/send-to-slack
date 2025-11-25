#!/usr/bin/env bats
#
# Test file for send-to-slack.sh
#

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		echo "Failed to get git root" >&2
		exit 1
	fi

	SCRIPT="$GIT_ROOT/send-to-slack.sh"
	if [[ ! -f "$SCRIPT" ]]; then
		echo "Script not found: $SCRIPT" >&2
		exit 1
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
	source "$SCRIPT"

	SEND_TO_SLACK_ROOT="$GIT_ROOT"

	# Source parse-payload.sh for parse_payload function
	source "$SEND_TO_SLACK_ROOT/bin/parse-payload.sh"

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

	TEST_PAYLOAD_FILE=$(mktemp test-payload.XXXXXX)
	chmod 0600 "${TEST_PAYLOAD_FILE}"

	export SEND_TO_SLACK_ROOT
	export SLACK_BOT_USER_OAUTH_TOKEN
	export CHANNEL
	export MESSAGE
	export DRY_RUN
	export SHOW_METADATA
	export SHOW_PAYLOAD
	export TEST_PAYLOAD_FILE

	return 0
}

teardown() {
	[[ -n "$TEST_PAYLOAD_FILE" ]] && rm -f "$TEST_PAYLOAD_FILE"
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
# Mocks
########################################################
mock_curl_success() {
	#shellcheck disable=SC2329
	curl() {
		echo '{"ok": true}'
		return 0
	}

	export -f curl
}

mock_curl_failure() {
	#shellcheck disable=SC2329
	curl() {
		echo '{"ok": false, "error": "invalid_auth"}' >&2
		return 1
	}

	export -f curl
}

mock_curl_network_error() {
	#shellcheck disable=SC2091
	curl() {
		return 1
	}

	export -f curl
}

########################################################
# create_metadata
########################################################

@test "create_metadata:: creates metadata when show_metadata is true" {
	SHOW_METADATA="true"
	DRY_RUN="true"
	SHOW_PAYLOAD="false"
	local payload='{"channel": "#test", "text": "test"}'

	create_metadata "$payload"
	[[ -n "$METADATA" ]]
	echo "$METADATA" | jq -e '.[] | select(.name == "dry_run") | .value == "true"' >/dev/null
}

@test "create_metadata:: includes payload when show_payload is true" {
	SHOW_METADATA="true"
	DRY_RUN="false"
	SHOW_PAYLOAD="true"
	local payload='{"channel": "#test", "text": "test"}'

	create_metadata "$payload"
	[[ -n "$METADATA" ]]
	echo "$METADATA" | jq -e '.[] | select(.name == "payload")' >/dev/null
}

@test "create_metadata:: does nothing when show_metadata is false" {
	SHOW_METADATA="false"
	local payload='{"channel": "#test", "text": "test"}'

	create_metadata "$payload"
	[[ "$METADATA" == "[]" ]]
}

########################################################
# send_notification
########################################################

@test "send_notification:: skips API call when dry run enabled" {
	DRY_RUN="true"
	local payload='{"channel": "#test"}'

	run send_notification "$payload"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "DRY_RUN enabled"
}

@test "send_notification:: fails with missing token" {
	DRY_RUN="false"
	SLACK_BOT_USER_OAUTH_TOKEN=""
	local payload='{"channel": "#test"}'

	run send_notification "$payload"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "SLACK_BOT_USER_OAUTH_TOKEN is required"
}

@test "send_notification:: fails with missing payload" {
	DRY_RUN="false"
	SLACK_BOT_USER_OAUTH_TOKEN="test-token"

	run send_notification ""
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "payload is required"
}

@test "send_notification:: fails when curl fails" {
	mock_curl_failure
	DRY_RUN="false"
	local payload='{"channel": "#test"}'

	run send_notification "$payload"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "Failed to send notification"
}

@test "send_notification:: fails when Slack API returns error" {
	mock_curl_failure
	DRY_RUN="false"
	local payload='{"channel": "#test"}'

	run send_notification "$payload"
	[[ "$status" -eq 1 ]]
}

########################################################
# get_message_permalink
########################################################

mock_curl_permalink_success() {
	#shellcheck disable=SC2329
	curl() {
		if [[ "$*" == *"chat.getPermalink"* ]]; then
			echo '{"ok": true, "permalink": "https://workspace.slack.com/archives/C123456/p1234567890123456"}'
			return 0
		else
			echo '{"ok": true, "channel": "C123456", "ts": "1234567890.123456"}'
			return 0
		fi
	}

	export -f curl
}

@test "get_message_permalink:: extracts permalink from API call" {
	mock_curl_permalink_success
	DRY_RUN="false"
	SLACK_BOT_USER_OAUTH_TOKEN="test-token"

	get_message_permalink "C123456" "1234567890.123456"
	[[ "$?" -eq 0 ]]
	[[ "$NOTIFICATION_PERMALINK" == "https://workspace.slack.com/archives/C123456/p1234567890123456" ]]
}

@test "get_message_permalink:: fails with missing channel" {
	SLACK_BOT_USER_OAUTH_TOKEN="test-token"

	run get_message_permalink "" "1234567890.123456"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "channel is required"
}

@test "get_message_permalink:: fails with missing message_ts" {
	SLACK_BOT_USER_OAUTH_TOKEN="test-token"

	run get_message_permalink "C123456" ""
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "message_ts is required"
}

@test "get_message_permalink:: fails with missing token" {
	SLACK_BOT_USER_OAUTH_TOKEN=""

	run get_message_permalink "C123456" "1234567890.123456"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "SLACK_BOT_USER_OAUTH_TOKEN is required"
}

mock_curl_permalink_failure() {
	#shellcheck disable=SC2329
	curl() {
		if [[ "$*" == *"chat.getPermalink"* ]]; then
			echo '{"ok": false, "error": "channel_not_found"}'
			return 0
		else
			echo '{"ok": true, "channel": "C123456", "ts": "1234567890.123456"}'
			return 0
		fi
	}

	export -f curl
}

@test "get_message_permalink:: fails when API returns error" {
	mock_curl_permalink_failure
	DRY_RUN="false"
	SLACK_BOT_USER_OAUTH_TOKEN="test-token"

	run get_message_permalink "C123456" "1234567890.123456"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "Channel not found"
}

########################################################
# crosspost_notification
########################################################

@test "crosspost_notification:: skips when crosspost is empty" {
	local input_payload
	input_payload=$(mktemp test-crosspost.XXXXXX)
	jq -n '{
		source: { slack_bot_user_oauth_token: "test-token" },
		params: { channel: "#test", blocks: [] }
	}' >"$input_payload"

	run crosspost_notification "$input_payload"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "crosspost is empty, skipping"

	rm -f "$input_payload"
}

@test "crosspost_notification:: skips when channels not set" {
	local input_payload
	input_payload=$(mktemp test-crosspost.XXXXXX)
	jq -n '{
		source: { slack_bot_user_oauth_token: "test-token" },
		params: {
			channel: "#test",
			blocks: [],
			crosspost: {
				channels: []
			}
		}
	}' >"$input_payload"

	run crosspost_notification "$input_payload"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "channels not set, skipping"

	rm -f "$input_payload"
}

@test "crosspost_notification:: uses default text when text not provided" {
	DRY_RUN="true"
	NOTIFICATION_PERMALINK="https://workspace.slack.com/archives/C123/p123"
	local input_payload
	input_payload=$(mktemp test-crosspost.XXXXXX)
	jq -n '{
		source: { slack_bot_user_oauth_token: "test-token" },
		params: {
			channel: "#test",
			blocks: [],
			crosspost: {
				channels: ["#channel1"]
			}
		}
	}' >"$input_payload"

	run crosspost_notification "$input_payload"
	[[ "$status" -eq 0 ]]

	rm -f "$input_payload"
}

@test "crosspost_notification:: uses custom text when provided" {
	DRY_RUN="true"
	NOTIFICATION_PERMALINK="https://workspace.slack.com/archives/C123/p123"
	local input_payload
	input_payload=$(mktemp test-crosspost.XXXXXX)
	jq -n '{
		source: { slack_bot_user_oauth_token: "test-token" },
		params: {
			channel: "#test",
			blocks: [],
			crosspost: {
				channels: ["#channel1"],
				text: "Custom crosspost message"
			}
		}
	}' >"$input_payload"

	run crosspost_notification "$input_payload"
	[[ "$status" -eq 0 ]]

	rm -f "$input_payload"
}

@test "crosspost_notification:: processes multiple channels" {
	DRY_RUN="true"
	NOTIFICATION_PERMALINK="https://workspace.slack.com/archives/C123/p123"
	local input_payload
	input_payload=$(mktemp test-crosspost.XXXXXX)
	jq -n '{
		source: { slack_bot_user_oauth_token: "test-token" },
		params: {
			channel: "#test",
			blocks: [],
			crosspost: {
				channels: ["#channel1", "#channel2", "#channel3"]
			}
		}
	}' >"$input_payload"

	run crosspost_notification "$input_payload"
	[[ "$status" -eq 0 ]]

	rm -f "$input_payload"
}

########################################################
# Health Check Tests
########################################################

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
	echo "$output" | grep -q "Testing Slack API connectivity"
}

@test "health_check:: --health-check flag works" {
	unset SLACK_BOT_USER_OAUTH_TOKEN
	run "$SCRIPT" --health-check
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "health_check"
}

@test "health_check:: -h flag works" {
	unset SLACK_BOT_USER_OAUTH_TOKEN
	run "$SCRIPT" -h
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "health_check"
}

########################################################
# Retry Logic Tests
########################################################

@test "retry_with_backoff:: succeeds on first attempt" {
	local attempt_file
	attempt_file=$(mktemp retry-attempt.XXXXXX)
	echo "0" >"$attempt_file"

	test_command() {
		local count
		count=$(cat "$attempt_file")
		count=$((count + 1))
		echo "$count" >"$attempt_file"
		return 0
	}
	export -f test_command
	export attempt_file

	run retry_with_backoff 3 'test_command'
	local attempt_count
	attempt_count=$(cat "$attempt_file")
	rm -f "$attempt_file"

	[[ "$status" -eq 0 ]]
	[[ $attempt_count -eq 1 ]]
}

@test "retry_with_backoff:: retries on failure and succeeds" {
	local attempt_file
	attempt_file=$(mktemp retry-attempt.XXXXXX)
	echo "0" >"$attempt_file"

	test_command() {
		local count
		count=$(cat "$attempt_file")
		count=$((count + 1))
		echo "$count" >"$attempt_file"
		if [[ $count -lt 2 ]]; then
			return 1
		fi
		return 0
	}
	export -f test_command
	export attempt_file

	RETRY_INITIAL_DELAY=0
	export RETRY_INITIAL_DELAY

	run retry_with_backoff 3 'test_command'
	local attempt_count
	attempt_count=$(cat "$attempt_file")
	rm -f "$attempt_file"

	[[ "$status" -eq 0 ]]
	[[ $attempt_count -eq 2 ]]
}

@test "retry_with_backoff:: exhausts all retries on persistent failure" {
	local attempt_file
	attempt_file=$(mktemp retry-attempt.XXXXXX)
	echo "0" >"$attempt_file"

	test_command() {
		local count
		count=$(cat "$attempt_file")
		count=$((count + 1))
		echo "$count" >"$attempt_file"
		return 1
	}
	export -f test_command
	export attempt_file

	RETRY_INITIAL_DELAY=0
	RETRY_MAX_ATTEMPTS=3
	export RETRY_INITIAL_DELAY
	export RETRY_MAX_ATTEMPTS

	run retry_with_backoff 3 'test_command'
	local attempt_count
	attempt_count=$(cat "$attempt_file")
	rm -f "$attempt_file"

	[[ "$status" -eq 1 ]]
	[[ $attempt_count -eq 3 ]]
	echo "$output" | grep -q "All 3 attempts failed"
}

@test "retry_with_backoff:: respects RETRY_MAX_ATTEMPTS" {
	local attempt_file
	attempt_file=$(mktemp retry-attempt.XXXXXX)
	echo "0" >"$attempt_file"

	test_command() {
		local count
		count=$(cat "$attempt_file")
		count=$((count + 1))
		echo "$count" >"$attempt_file"
		return 1
	}
	export -f test_command
	export attempt_file

	RETRY_INITIAL_DELAY=0
	RETRY_MAX_ATTEMPTS=5
	export RETRY_INITIAL_DELAY
	export RETRY_MAX_ATTEMPTS

	run retry_with_backoff 5 'test_command'
	local attempt_count
	attempt_count=$(cat "$attempt_file")
	rm -f "$attempt_file"

	[[ "$status" -eq 1 ]]
	[[ $attempt_count -eq 5 ]]
}

@test "retry_with_backoff:: uses exponential backoff" {
	local attempt_file
	attempt_file=$(mktemp retry-attempt.XXXXXX)
	echo "0" >"$attempt_file"

	test_command() {
		local count
		count=$(cat "$attempt_file")
		count=$((count + 1))
		echo "$count" >"$attempt_file"
		return 1
	}
	export -f test_command
	export attempt_file

	RETRY_INITIAL_DELAY=1
	RETRY_BACKOFF_MULTIPLIER=2
	RETRY_MAX_ATTEMPTS=3
	export RETRY_INITIAL_DELAY
	export RETRY_BACKOFF_MULTIPLIER
	export RETRY_MAX_ATTEMPTS

	start_time=$(date +%s)
	run retry_with_backoff 3 'test_command'
	end_time=$(date +%s)
	elapsed=$((end_time - start_time))
	rm -f "$attempt_file"

	[[ $elapsed -ge 2 ]]
	[[ "$status" -eq 1 ]]
}

@test "retry_with_backoff:: respects RETRY_MAX_DELAY" {
	local attempt_file
	attempt_file=$(mktemp retry-attempt.XXXXXX)
	echo "0" >"$attempt_file"

	test_command() {
		local count
		count=$(cat "$attempt_file")
		count=$((count + 1))
		echo "$count" >"$attempt_file"
		return 1
	}
	export -f test_command
	export attempt_file

	RETRY_INITIAL_DELAY=2
	RETRY_BACKOFF_MULTIPLIER=10
	RETRY_MAX_DELAY=3
	RETRY_MAX_ATTEMPTS=3
	export RETRY_INITIAL_DELAY
	export RETRY_BACKOFF_MULTIPLIER
	export RETRY_MAX_DELAY
	export RETRY_MAX_ATTEMPTS

	start_time=$(date +%s)
	run retry_with_backoff 3 'test_command'
	end_time=$(date +%s)
	elapsed=$((end_time - start_time))
	rm -f "$attempt_file"

	[[ "$status" -eq 1 ]]
	[[ $elapsed -lt 15 ]]
}

@test "retry_with_backoff:: uses default RETRY_MAX_ATTEMPTS when not specified" {
	local attempt_file
	attempt_file=$(mktemp retry-attempt.XXXXXX)
	echo "0" >"$attempt_file"

	test_command() {
		local count
		count=$(cat "$attempt_file")
		count=$((count + 1))
		echo "$count" >"$attempt_file"
		return 1
	}
	export -f test_command
	export attempt_file

	RETRY_MAX_ATTEMPTS=2
	RETRY_INITIAL_DELAY=0
	export RETRY_MAX_ATTEMPTS
	export RETRY_INITIAL_DELAY

	run retry_with_backoff "" 'test_command'
	local attempt_count
	attempt_count=$(cat "$attempt_file")
	rm -f "$attempt_file"

	[[ "$status" -eq 1 ]]
	[[ $attempt_count -eq 2 ]]
}

########################################################
# Enhanced Error Handling Tests
########################################################

@test "handle_slack_api_error:: handles rate_limited error" {
	local response='{"ok": false, "error": "rate_limited"}'
	run handle_slack_api_error "$response" "test_context"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Rate limited"
	echo "$output" | grep -q "retry logic"
	echo "$output" | grep -q "test_context"
}

@test "handle_slack_api_error:: handles invalid_auth error" {
	local response='{"ok": false, "error": "invalid_auth"}'
	run handle_slack_api_error "$response" "test_context"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Authentication failed"
	echo "$output" | grep -q "SLACK_BOT_USER_OAUTH_TOKEN"
	echo "$output" | grep -q "test_context"
}

@test "handle_slack_api_error:: handles channel_not_found error" {
	local response='{"ok": false, "error": "channel_not_found"}'
	run handle_slack_api_error "$response" "test_context"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Channel not found"
	echo "$output" | grep -q "test_context"
}

@test "handle_slack_api_error:: handles not_in_channel error" {
	local response='{"ok": false, "error": "not_in_channel"}'
	run handle_slack_api_error "$response" "test_context"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Bot is not in the specified channel"
	echo "$output" | grep -q "Invite the bot"
}

@test "handle_slack_api_error:: handles missing_scope error with needed scope" {
	local response='{"ok": false, "error": "missing_scope", "needed": "channels:read"}'
	run handle_slack_api_error "$response" "test_context"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Missing required OAuth scope"
	echo "$output" | grep -q "channels:read"
}

@test "handle_slack_api_error:: handles unknown error" {
	local response='{"ok": false, "error": "unknown_error"}'
	run handle_slack_api_error "$response" "test_context"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Slack API error: unknown_error"
	echo "$output" | grep -q "test_context"
}

@test "handle_slack_api_error:: works without context" {
	local response='{"ok": false, "error": "rate_limited"}'
	run handle_slack_api_error "$response"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Rate limited"
	! echo "$output" | grep -q "Context:"
}

########################################################
# Input options
########################################################

@test "main:: accepts -file option with valid file" {
	create_test_payload

	export SEND_TO_SLACK_ROOT="$GIT_ROOT"
	run "$SCRIPT" -file "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "version"
	echo "$output" | grep -q "timestamp"
	echo "$output" | grep -q "main:: parsing payload"
}

@test "main:: accepts --file option with valid file" {
	create_test_payload

	export SEND_TO_SLACK_ROOT="$GIT_ROOT"
	run "$SCRIPT" --file "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "version"
	echo "$output" | grep -q "timestamp"
	echo "$output" | grep -q "main:: parsing payload"
}

@test "main:: fails when -file option is specified without file path" {
	export SEND_TO_SLACK_ROOT="$GIT_ROOT"
	run "$SCRIPT" -file
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "process_input::"
	echo "$output" | grep -q "requires a file path argument"
}

@test "main:: fails when --file option is specified without file path" {
	export SEND_TO_SLACK_ROOT="$GIT_ROOT"
	run "$SCRIPT" --file
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "process_input::"
	echo "$output" | grep -q "requires a file path argument"
}

@test "main:: fails when file does not exist" {
	local nonexistent_file
	nonexistent_file="/tmp/nonexistent-file-$(date +%s).json"

	export SEND_TO_SLACK_ROOT="$GIT_ROOT"
	run "$SCRIPT" -file "$nonexistent_file"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "process_input::"
	echo "$output" | grep -q "input file does not exist"
}

@test "main:: fails when file is not readable" {
	local unreadable_file
	unreadable_file=$(mktemp unreadable.XXXXXX)
	chmod 000 "$unreadable_file"

	export SEND_TO_SLACK_ROOT="$GIT_ROOT"
	run "$SCRIPT" -file "$unreadable_file"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "process_input::"
	echo "$output" | grep -q "input file is not readable"

	chmod 600 "$unreadable_file"
	rm -f "$unreadable_file"
}

@test "main:: fails when file is empty" {
	local empty_file
	empty_file=$(mktemp empty.XXXXXX)
	touch "$empty_file"

	export SEND_TO_SLACK_ROOT="$GIT_ROOT"
	run "$SCRIPT" -file "$empty_file"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "process_input::"
	echo "$output" | grep -q "input file is empty"

	rm -f "$empty_file"
}

@test "main:: uses file and ignores stdin when both are provided" {
	create_test_payload

	export SEND_TO_SLACK_ROOT="$GIT_ROOT"
	run "$SCRIPT" -file "$TEST_PAYLOAD_FILE" <"$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "main:: finished running send-to-slack.sh successfully"
}

@test "main:: fails when no input is provided" {
	export SEND_TO_SLACK_ROOT="$GIT_ROOT"
	# When stdin is empty (/dev/null), script will try to read and detect empty input
	run "$SCRIPT" </dev/null
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "process_input::"
	echo "$output" | grep -q "no input received on stdin"
}

@test "main:: fails when -file option is specified multiple times" {
	create_test_payload

	export SEND_TO_SLACK_ROOT="$GIT_ROOT"
	run "$SCRIPT" -file "$TEST_PAYLOAD_FILE" -file "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "process_input::"
	echo "$output" | grep -q "can only be specified once"
}

@test "main:: fails with unknown option" {
	export SEND_TO_SLACK_ROOT="$GIT_ROOT"
	run "$SCRIPT" --unknown-option
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "process_input::"
	echo "$output" | grep -q "unknown option"
}

@test "main:: file input works same as stdin input" {
	create_test_payload

	# Test with stdin
	export SEND_TO_SLACK_ROOT="$GIT_ROOT"
	run "$SCRIPT" <"$TEST_PAYLOAD_FILE"
	local stdin_status="$status"
	local stdin_output="$output"

	# Test with file option
	export SEND_TO_SLACK_ROOT="$GIT_ROOT"
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
