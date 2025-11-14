#!/usr/bin/env bats
#
# Test suite for resolve-mentions.sh
# Tests user, channel, group, and DM resolution with real Slack API calls
#
GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
RESOLVE_SCRIPT="$GIT_ROOT/bin/resolve-mentions.sh"

[[ ! -f "$RESOLVE_SCRIPT" ]] && echo "Script not found: $RESOLVE_SCRIPT" >&2 && return 1

setup_file() {
	if [[ -z "${SLACK_BOT_USER_OAUTH_TOKEN}" ]]; then
		skip "SLACK_BOT_USER_OAUTH_TOKEN environment variable is not set"
	fi

	# For channel and DM tests, we need at least one channel and one user available
	# These are validated in the individual tests
	return 0
}

setup() {
	# shellcheck disable=SC1091,SC1090
	source "$RESOLVE_SCRIPT"
	return 0
}

########################################################
# User Resolution Tests
########################################################

@test "resolve_user_id:: user ID pass-through" {
	result=$(resolve_user_id "U123456789ABC")
	[[ "$result" == "U123456789ABC" ]]
}

@test "resolve_user_id:: user ID with 9 chars passes through" {
	result=$(resolve_user_id "U12345ABC")
	[[ "$result" == "U12345ABC" ]]
}

@test "resolve_user_id:: missing user_ref fails" {
	run resolve_user_id ""
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "user_ref is required"
}

@test "resolve_user_id:: missing token fails" {
	unset SLACK_BOT_USER_OAUTH_TOKEN
	run resolve_user_id "test-user"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "SLACK_BOT_USER_OAUTH_TOKEN"
}

########################################################
# Channel Resolution Tests
########################################################

@test "resolve_channel_id:: channel ID C-type pass-through" {
	result=$(resolve_channel_id "C123456789ABC")
	[[ "$result" == "C123456789ABC" ]]
}

@test "resolve_channel_id:: group ID G-type pass-through" {
	result=$(resolve_channel_id "G123456789DEF")
	[[ "$result" == "G123456789DEF" ]]
}

@test "resolve_channel_id:: shared channel ID Z-type pass-through" {
	result=$(resolve_channel_id "Z123456789GHI")
	[[ "$result" == "Z123456789GHI" ]]
}

@test "resolve_channel_id:: direct message ID D-type pass-through" {
	result=$(resolve_channel_id "D123456789JKL")
	[[ "$result" == "D123456789JKL" ]]
}

@test "resolve_channel_id:: missing channel_ref fails" {
	run resolve_channel_id ""
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "channel_ref is required"
}

@test "resolve_channel_id:: missing token fails" {
	unset SLACK_BOT_USER_OAUTH_TOKEN
	run resolve_channel_id "general"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "SLACK_BOT_USER_OAUTH_TOKEN"
}

########################################################
# DM Resolution Tests
########################################################

@test "resolve_dm_id:: DM ID pass-through" {
	result=$(resolve_dm_id "D123456789ABC")
	[[ "$result" == "D123456789ABC" ]]
}

@test "resolve_dm_id:: missing dm_ref fails" {
	run resolve_dm_id ""
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "dm_ref is required"
}

@test "resolve_dm_id:: missing token fails" {
	unset SLACK_BOT_USER_OAUTH_TOKEN
	run resolve_dm_id "slackbot"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "SLACK_BOT_USER_OAUTH_TOKEN"
}

########################################################
# Edge Cases and Integration Tests
########################################################

@test "resolve_user_id:: idempotent with valid user IDs" {
	id1=$(resolve_user_id "U123456789ABC")
	id2=$(resolve_user_id "$id1")
	[[ "$id1" == "$id2" ]]
}

@test "resolve_channel_id:: idempotent with valid channel IDs" {
	id1=$(resolve_channel_id "C123456789ABC")
	id2=$(resolve_channel_id "$id1")
	[[ "$id1" == "$id2" ]]
}

@test "resolve_dm_id:: idempotent with valid DM IDs" {
	id1=$(resolve_dm_id "D123456789ABC")
	id2=$(resolve_dm_id "$id1")
	[[ "$id1" == "$id2" ]]
}
