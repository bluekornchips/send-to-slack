#!/usr/bin/env bats
#
# Tests for lib/slack/api/send.sh
#

load "api-test-helper.sh"

setup_file() {
	api_test_setup_file
	return 0
}

setup() {
	api_test_setup
	return 0
}

teardown() {
	api_test_teardown
	return 0
}

# send_notification
########################################################

@test "send_notification:: skips API call when dry run enabled" {
	DRY_RUN="true"
	export DRY_RUN
	DELIVERY_METHOD="api"
	local payload=$(
		cat <<-'EOF'
			{
			  "channel": "#test"
			}
		EOF
	)

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
	local payload=$(
		cat <<-'EOF'
			{
			  "channel": "#test"
			}
		EOF
	)

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
	local payload=$(
		cat <<-'EOF'
			{
			  "channel": "#test"
			}
		EOF
	)

	run send_notification "$payload"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "Authentication failed"
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
	local payload=$(
		cat <<-'EOF'
			{
			  "channel": "#test"
			}
		EOF
	)

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
