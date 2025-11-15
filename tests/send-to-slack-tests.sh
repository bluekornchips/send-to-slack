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
	SHOW_PAYLOAD="false"
	BLOCKS="$(jq -n '[
		{
			"type": "section",
			"text": {
				"type": "plain_text",
				"text": "test message"
			}
		}
	]')"

	TEST_PAYLOAD_FILE=$(mktemp /tmp/test-payload.XXXXXX)
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
	echo "$METADATA" | jq -e '.metadata[] | select(.name == "dry_run") | .value == "true"' >/dev/null
}

@test "create_metadata:: includes payload when show_payload is true" {
	SHOW_METADATA="true"
	DRY_RUN="false"
	SHOW_PAYLOAD="true"
	local payload='{"channel": "#test", "text": "test"}'

	create_metadata "$payload"
	[[ -n "$METADATA" ]]
	echo "$METADATA" | jq -e '.metadata[] | select(.name == "payload")' >/dev/null
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
	echo "$output" | grep -q "curl failed to send request"
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
	echo "$output" | grep -q "Slack API returned error"
}

########################################################
# crosspost_notification
########################################################

@test "crosspost_notification:: skips when crosspost is empty" {
	local input_payload
	input_payload=$(mktemp /tmp/test-crosspost.XXXXXX)
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
	input_payload=$(mktemp /tmp/test-crosspost.XXXXXX)
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
	input_payload=$(mktemp /tmp/test-crosspost.XXXXXX)
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
	input_payload=$(mktemp /tmp/test-crosspost.XXXXXX)
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
	input_payload=$(mktemp /tmp/test-crosspost.XXXXXX)
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
	unreadable_file=$(mktemp /tmp/unreadable.XXXXXX)
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
	empty_file=$(mktemp /tmp/empty.XXXXXX)
	touch "$empty_file"

	export SEND_TO_SLACK_ROOT="$GIT_ROOT"
	run "$SCRIPT" -file "$empty_file"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "process_input::"
	echo "$output" | grep -q "input file is empty"

	rm -f "$empty_file"
}

@test "main:: fails when both stdin and -file are provided" {
	create_test_payload

	export SEND_TO_SLACK_ROOT="$GIT_ROOT"
	run "$SCRIPT" -file "$TEST_PAYLOAD_FILE" <"$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "process_input::"
	echo "$output" | grep -q "cannot use both -file|--file option and stdin input"
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
