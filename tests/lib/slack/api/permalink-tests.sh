#!/usr/bin/env bats
#
# Tests for lib/slack/api/permalink.sh
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

# get_message_permalink
########################################################

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
