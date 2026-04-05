#!/usr/bin/env bats
#
# Tests for lib/slack/api.sh
#

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		fail "Failed to get git root"
	fi

	SCRIPT="$GIT_ROOT/lib/slack/api.sh"
	if [[ ! -f "$SCRIPT" ]]; then
		fail "Script not found: $SCRIPT"
	fi

	export GIT_ROOT
	export SCRIPT

	return 0
}

setup() {
	source "$SCRIPT"

	SLACK_BOT_USER_OAUTH_TOKEN="test-token"
	DRY_RUN="true"
	RETRY_INITIAL_DELAY=1
	RETRY_MAX_ATTEMPTS=3
	RETRY_MAX_DELAY=60
	RETRY_BACKOFF_MULTIPLIER=2
	DELIVERY_METHOD="api"

	_SLACK_WORKSPACE=$(mktemp -d "${BATS_TEST_TMPDIR}/slack-api-tests.workspace.XXXXXX")
	export _SLACK_WORKSPACE

	export SLACK_BOT_USER_OAUTH_TOKEN
	export DRY_RUN
	export RETRY_INITIAL_DELAY
	export RETRY_MAX_ATTEMPTS
	export RETRY_MAX_DELAY
	export RETRY_INITIAL_DELAY
	export DELIVERY_METHOD

	return 0
}

teardown() {
	[[ -n "${_SLACK_WORKSPACE:-}" ]] && rm -rf "$_SLACK_WORKSPACE"
	[[ -n "${attempt_file:-}" ]] && rm -f "$attempt_file"
	[[ -n "${sleep_log:-}" ]] && rm -f "$sleep_log"
	[[ -n "${url_capture:-}" ]] && rm -f "$url_capture"
	return 0
}

########################################################
# Mocks
########################################################

mock_curl_failure() {
	curl() {
		echo '{"ok": false, "error": "invalid_auth"}' >&2
		return 1
	}

	export -f curl
}

########################################################
# _is_error_in_list
########################################################

@test "_is_error_in_list:: returns 0 when code is in list" {
	if _is_error_in_list "invalid_auth" "${ERROR_CODES_TRUE_FAILURES[@]}"; then
		return 0
	fi
	return 1
}

@test "_is_error_in_list:: returns 1 when code is not in list" {
	if _is_error_in_list "rate_limited" "${ERROR_CODES_TRUE_FAILURES[@]}"; then
		return 1
	fi
	return 0
}

########################################################
# send_notification
########################################################

@test "send_notification:: skips API call when dry run enabled" {
	DRY_RUN="true"
	export DRY_RUN
	DELIVERY_METHOD="api"
	local payload='{"channel": "#test"}'

	run send_notification "$payload"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "DRY_RUN enabled"
}

@test "send_notification:: fails with missing token" {
	DRY_RUN="false"
	export DRY_RUN
	DELIVERY_METHOD="api"
	SLACK_BOT_USER_OAUTH_TOKEN=""
	export SLACK_BOT_USER_OAUTH_TOKEN
	local payload='{"channel": "#test"}'

	run send_notification "$payload"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "SLACK_BOT_USER_OAUTH_TOKEN is required"
}

@test "send_notification:: fails with missing payload" {
	DRY_RUN="false"
	export DRY_RUN
	DELIVERY_METHOD="api"
	SLACK_BOT_USER_OAUTH_TOKEN="test-token"
	export SLACK_BOT_USER_OAUTH_TOKEN

	run send_notification ""
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "payload is required"
}

@test "send_notification:: fails when curl fails" {
	mock_curl_failure
	DRY_RUN="false"
	export DRY_RUN
	DELIVERY_METHOD="api"
	RETRY_INITIAL_DELAY=0
	export RETRY_INITIAL_DELAY
	SLACK_BOT_USER_OAUTH_TOKEN="test-token"
	export SLACK_BOT_USER_OAUTH_TOKEN
	local payload='{"channel": "#test"}'

	run send_notification "$payload"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "Failed to send notification"
}

@test "send_notification:: fails when Slack API returns error" {
	mock_curl_failure
	DRY_RUN="false"
	export DRY_RUN
	DELIVERY_METHOD="api"
	RETRY_INITIAL_DELAY=0
	export RETRY_INITIAL_DELAY
	SLACK_BOT_USER_OAUTH_TOKEN="test-token"
	export SLACK_BOT_USER_OAUTH_TOKEN
	local payload='{"channel": "#test"}'

	run send_notification "$payload"
	[[ "$status" -eq 1 ]]
}

########################################################
# _send_by_api
########################################################

@test "_send_by_api:: uses chat.postEphemeral URL when EPHEMERAL_USER is set" {
	local url_capture
	url_capture=$(mktemp "${BATS_TEST_TMPDIR}/slack-api-tests.api-url.XXXXXX")
	export url_capture

	EPHEMERAL_USER="U123"
	export EPHEMERAL_USER
	export SLACK_BOT_USER_OAUTH_TOKEN

	curl() {
		local arg
		for arg in "$@"; do
			case "$arg" in
			http*)
				printf '%s\n' "$arg" >>"$url_capture"
				;;
			esac
		done
		printf '%s\n' '{"ok": true}'
		printf '%s\n' '200'
		return 0
	}
	export -f curl

	local pf
	pf=$(mktemp "${BATS_TEST_TMPDIR}/slack-api-tests.api-payload.XXXXXX")
	echo '{"channel":"#c"}' >"$pf"

	run _send_by_api "$pf" '{"channel":"#c"}'
	rm -f "$pf"

	[[ "$status" -eq 0 ]]
	grep -q "chat.postEphemeral" "$url_capture"
	rm -f "$url_capture"
}

@test "_send_by_api:: uses chat.postMessage URL when EPHEMERAL_USER is unset" {
	local url_capture
	url_capture=$(mktemp "${BATS_TEST_TMPDIR}/slack-api-tests.api-url2.XXXXXX")
	export url_capture

	unset EPHEMERAL_USER
	SLACK_BOT_USER_OAUTH_TOKEN="test-token"
	export SLACK_BOT_USER_OAUTH_TOKEN

	curl() {
		local arg
		for arg in "$@"; do
			case "$arg" in
			http*)
				printf '%s\n' "$arg" >>"$url_capture"
				;;
			esac
		done
		printf '%s\n' '{"ok": true}'
		printf '%s\n' '200'
		return 0
	}
	export -f curl

	local pf
	pf=$(mktemp "${BATS_TEST_TMPDIR}/slack-api-tests.api-payload2.XXXXXX")
	echo '{"channel":"#c"}' >"$pf"

	run _send_by_api "$pf" '{"channel":"#c"}'
	rm -f "$pf"

	[[ "$status" -eq 0 ]]
	grep -q "chat.postMessage" "$url_capture"
	rm -f "$url_capture"
}

########################################################
# _send_by_webhook
########################################################

@test "_send_by_webhook:: succeeds on 2xx response" {
	WEBHOOK_URL="https://hooks.slack.com/services/test"
	export WEBHOOK_URL

	curl() {
		printf '%s\n' 'ok'
		printf '%s\n' '204'
		return 0
	}
	export -f curl

	local pf
	pf=$(mktemp "${BATS_TEST_TMPDIR}/slack-api-tests.wh-payload.XXXXXX")
	echo '{}' >"$pf"

	run _send_by_webhook "$pf"
	rm -f "$pf"

	[[ "$status" -eq 0 ]]
}

@test "_send_by_webhook:: fails on non-2xx response" {
	WEBHOOK_URL="https://hooks.slack.com/services/test"
	export WEBHOOK_URL

	curl() {
		printf '%s\n' 'err'
		printf '%s\n' '500'
		return 0
	}
	export -f curl

	local pf
	pf=$(mktemp "${BATS_TEST_TMPDIR}/slack-api-tests.wh-payload2.XXXXXX")
	echo '{}' >"$pf"

	run _send_by_webhook "$pf"
	rm -f "$pf"

	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "webhook HTTP error code"
}

########################################################
# get_message_permalink
########################################################

mock_curl_permalink_success() {
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
	export SLACK_BOT_USER_OAUTH_TOKEN

	if ! get_message_permalink "C123456" "1234567890.123456"; then
		echo "get_message_permalink failed" >&2
		return 1
	fi

	[[ "$NOTIFICATION_PERMALINK" == "https://workspace.slack.com/archives/C123456/p1234567890123456" ]]
}

@test "get_message_permalink:: fails with missing channel" {
	SLACK_BOT_USER_OAUTH_TOKEN="test-token"
	export SLACK_BOT_USER_OAUTH_TOKEN

	run get_message_permalink "" "1234567890.123456"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "channel is required"
}

@test "get_message_permalink:: fails with missing message_ts" {
	SLACK_BOT_USER_OAUTH_TOKEN="test-token"
	export SLACK_BOT_USER_OAUTH_TOKEN

	run get_message_permalink "C123456" ""
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "message_ts is required"
}

@test "get_message_permalink:: fails with missing token" {
	SLACK_BOT_USER_OAUTH_TOKEN=""
	export SLACK_BOT_USER_OAUTH_TOKEN

	run get_message_permalink "C123456" "1234567890.123456"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "SLACK_BOT_USER_OAUTH_TOKEN is required"
}

mock_curl_permalink_failure() {
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
	export SLACK_BOT_USER_OAUTH_TOKEN

	run get_message_permalink "C123456" "1234567890.123456"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "Channel not found"
}

########################################################
# Retry Logic Tests
########################################################

@test "retry_with_backoff:: succeeds on first attempt" {
	local attempt_file
	attempt_file=$(mktemp "${BATS_TEST_TMPDIR}/slack-api-tests.retry-attempt.XXXXXX")
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

	run retry_with_backoff 3 test_command
	local attempt_count
	attempt_count=$(cat "$attempt_file")
	rm -f "$attempt_file"

	[[ "$status" -eq 0 ]]
	[[ $attempt_count -eq 1 ]]
}

@test "retry_with_backoff:: retries on failure and succeeds" {
	local attempt_file
	attempt_file=$(mktemp "${BATS_TEST_TMPDIR}/slack-api-tests.retry-attempt.XXXXXX")
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

	run retry_with_backoff 3 test_command
	local attempt_count
	attempt_count=$(cat "$attempt_file")
	rm -f "$attempt_file"

	[[ "$status" -eq 0 ]]
	[[ $attempt_count -eq 2 ]]
}

@test "retry_with_backoff:: exhausts all retries on persistent failure" {
	local attempt_file
	attempt_file=$(mktemp "${BATS_TEST_TMPDIR}/slack-api-tests.retry-attempt.XXXXXX")
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

	run retry_with_backoff 3 test_command
	local attempt_count
	attempt_count=$(cat "$attempt_file")
	rm -f "$attempt_file"

	[[ "$status" -eq 1 ]]
	[[ $attempt_count -eq 3 ]]
	echo "$output" | grep -q "All 3 attempts failed"
}

@test "retry_with_backoff:: respects RETRY_MAX_ATTEMPTS" {
	local attempt_file
	attempt_file=$(mktemp "${BATS_TEST_TMPDIR}/slack-api-tests.retry-attempt.XXXXXX")
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

	run retry_with_backoff 5 test_command
	local attempt_count
	attempt_count=$(cat "$attempt_file")
	rm -f "$attempt_file"

	[[ "$status" -eq 1 ]]
	[[ $attempt_count -eq 5 ]]
}

@test "retry_with_backoff:: uses exponential backoff" {
	local attempt_file sleep_log
	attempt_file=$(mktemp "${BATS_TEST_TMPDIR}/slack-api-tests.retry-attempt.XXXXXX")
	sleep_log=$(mktemp "${BATS_TEST_TMPDIR}/slack-api-tests.sleep-log.XXXXXX")
	echo "0" >"$attempt_file"

	test_command() {
		local count
		count=$(cat "$attempt_file")
		count=$((count + 1))
		echo "$count" >"$attempt_file"
		return 1
	}
	sleep() { echo "$1" >>"$sleep_log"; }
	export -f test_command
	export -f sleep
	export attempt_file
	export sleep_log

	RETRY_INITIAL_DELAY=1
	RETRY_BACKOFF_MULTIPLIER=2
	RETRY_MAX_ATTEMPTS=3
	export RETRY_INITIAL_DELAY
	export RETRY_BACKOFF_MULTIPLIER
	export RETRY_MAX_ATTEMPTS

	run retry_with_backoff 3 test_command
	rm -f "$attempt_file"

	[[ "$status" -eq 1 ]]
	# 3 attempts produce 2 inter-attempt sleeps: 1s then 2s
	[[ "$(sed -n '1p' "$sleep_log")" == "1" ]]
	[[ "$(sed -n '2p' "$sleep_log")" == "2" ]]
	rm -f "$sleep_log"
}

@test "retry_with_backoff:: respects RETRY_MAX_DELAY" {
	local attempt_file sleep_log
	attempt_file=$(mktemp "${BATS_TEST_TMPDIR}/slack-api-tests.retry-attempt.XXXXXX")
	sleep_log=$(mktemp "${BATS_TEST_TMPDIR}/slack-api-tests.sleep-log.XXXXXX")
	echo "0" >"$attempt_file"

	test_command() {
		local count
		count=$(cat "$attempt_file")
		count=$((count + 1))
		echo "$count" >"$attempt_file"
		return 1
	}
	sleep() { echo "$1" >>"$sleep_log"; }
	export -f test_command
	export -f sleep
	export attempt_file
	export sleep_log

	RETRY_INITIAL_DELAY=2
	RETRY_BACKOFF_MULTIPLIER=10
	RETRY_MAX_DELAY=3
	RETRY_MAX_ATTEMPTS=3
	export RETRY_INITIAL_DELAY
	export RETRY_BACKOFF_MULTIPLIER
	export RETRY_MAX_DELAY
	export RETRY_MAX_ATTEMPTS

	run retry_with_backoff 3 test_command
	rm -f "$attempt_file"

	[[ "$status" -eq 1 ]]
	# 3 attempts produce 2 inter-attempt sleeps: 2s then min(20,3)=3s
	[[ "$(sed -n '1p' "$sleep_log")" == "2" ]]
	[[ "$(sed -n '2p' "$sleep_log")" == "3" ]]
	rm -f "$sleep_log"
}

@test "retry_with_backoff:: uses default RETRY_MAX_ATTEMPTS when not specified" {
	local attempt_file
	attempt_file=$(mktemp "${BATS_TEST_TMPDIR}/slack-api-tests.retry-attempt.XXXXXX")
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

	run retry_with_backoff "" test_command
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
	[[ "$output" != *"Context:"* ]]
}

########################################################
# _send_update_by_api
########################################################

@test "_send_update_by_api:: returns 2 on message_not_found" {
	SLACK_BOT_USER_OAUTH_TOKEN="test-token"

	curl() {
		printf '%s\n' '{"ok": false, "error": "message_not_found"}'
		printf '%s\n' '200'
		return 0
	}
	export -f curl

	local pf
	pf=$(mktemp "${BATS_TEST_TMPDIR}/slack-api-tests.upd-payload.XXXXXX")
	echo '{"channel":"C1","ts":"1","text":"x"}' >"$pf"

	run _send_update_by_api "$pf" '{}'
	rm -f "$pf"

	[[ "$status" -eq 2 ]]
}

@test "_send_update_by_api:: posts to chat.update URL" {
	local url_capture
	url_capture=$(mktemp "${BATS_TEST_TMPDIR}/slack-api-tests.upd-url.XXXXXX")
	export url_capture

	SLACK_BOT_USER_OAUTH_TOKEN="test-token"

	curl() {
		local arg
		for arg in "$@"; do
			case "$arg" in
			http*)
				printf '%s\n' "$arg" >>"$url_capture"
				;;
			esac
		done
		printf '%s\n' '{"ok": true, "channel": "C1", "ts": "2"}'
		printf '%s\n' '200'
		return 0
	}
	export -f curl

	local pf
	pf=$(mktemp "${BATS_TEST_TMPDIR}/slack-api-tests.upd-payload2.XXXXXX")
	echo '{"channel":"C1","ts":"1","text":"x"}' >"$pf"

	run _send_update_by_api "$pf" '{}'
	rm -f "$pf"

	[[ "$status" -eq 0 ]]
	grep -q "chat.update" "$url_capture"
	rm -f "$url_capture"
}

########################################################
# update_message
########################################################

@test "update_message:: skips API call when dry run enabled" {
	DRY_RUN="true"
	SLACK_BOT_USER_OAUTH_TOKEN="test-token"

	run update_message "C1" "123.456" '{"channel":"C1","text":"hi"}'
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "DRY_RUN"
}

@test "update_message:: fails when delivery is webhook" {
	DRY_RUN="false"
	DELIVERY_METHOD="webhook"

	run update_message "C1" "123.456" '{"text":"hi"}'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "requires API delivery"
}

@test "update_message:: fails with empty channel" {
	DRY_RUN="false"

	run update_message "" "123.456" '{"text":"hi"}'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "channel is required"
}

@test "update_message:: fails with empty message_ts" {
	DRY_RUN="false"

	run update_message "C1" "" '{"text":"hi"}'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "message_ts is required"
}

@test "update_message:: succeeds when API returns ok" {
	DRY_RUN="false"

	local url_capture
	url_capture=$(mktemp "${BATS_TEST_TMPDIR}/slack-api-tests.upd-msg-url.XXXXXX")
	export url_capture

	curl() {
		local arg
		for arg in "$@"; do
			case "$arg" in
			http*)
				printf '%s\n' "$arg" >>"$url_capture"
				;;
			esac
		done
		if [[ "$*" == *"chat.getPermalink"* ]]; then
			printf '%s\n' '{"ok": true, "permalink": "https://example.com/p"}'
			return 0
		fi
		printf '%s\n' '{"ok": true, "channel": "C111", "ts": "1712000000.000200"}'
		printf '%s\n' '200'
		return 0
	}
	export -f curl

	if ! update_message "C111" "1712000000.000100" '{"text":"updated"}'; then
		rm -f "$url_capture"
		return 1
	fi

	grep -q "chat.update" "$url_capture"
	local got_ts
	got_ts=$(echo "${SEND_NOTIFICATION_RESPONSE:-}" | jq -r '.ts')
	[[ "$got_ts" == "1712000000.000200" ]]
	rm -f "$url_capture"
}

@test "update_message:: strips bot identity fields from chat.update request body" {
	DRY_RUN="false"

	local body_capture
	body_capture=$(mktemp "${BATS_TEST_TMPDIR}/slack-api-tests.update-body.XXXXXX")

	curl() {
		local prev=""
		for arg in "$@"; do
			if [[ "$prev" == "-d" ]] && [[ "$arg" == @* ]]; then
				local f="${arg#@}"
				cat "$f" >"$body_capture"
			fi
			prev="$arg"
		done
		if [[ "$*" == *"chat.getPermalink"* ]]; then
			printf '%s\n' '{"ok": true, "permalink": "https://example.com/p"}'
			return 0
		fi
		printf '%s\n' '{"ok": true, "channel": "C111", "ts": "1712000000.000200"}'
		printf '%s\n' '200'
		return 0
	}
	export -f curl

	update_message "C111" "1712000000.000100" \
		'{"text":"updated","username":"Deploy Bot","icon_emoji":":ship:","icon_url":"https://example.com/i.png"}'

	jq -e 'has("username") | not' "$body_capture" >/dev/null
	jq -e 'has("icon_emoji") | not' "$body_capture" >/dev/null
	jq -e 'has("icon_url") | not' "$body_capture" >/dev/null
	jq -e '.channel == "C111" and .ts == "1712000000.000100"' "$body_capture" >/dev/null
	rm -f "$body_capture"
}
