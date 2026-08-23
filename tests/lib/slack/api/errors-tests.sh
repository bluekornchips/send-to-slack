#!/usr/bin/env bats
#
# Tests for lib/slack/api/errors.sh
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
# handle_slack_api_error
########################################################

@test "handle_slack_api_error:: handles rate_limited error" {
	local response=$(
		cat <<-'EOF'
			{
			  "ok": false,
			  "error": "rate_limited"
			}
		EOF
	)
	run handle_slack_api_error "$response" "test_context"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Rate limited"
	echo "$output" | grep -q "retry logic"
	echo "$output" | grep -q "test_context"
}

@test "handle_slack_api_error:: handles invalid_auth error" {
	local response=$(
		cat <<-'EOF'
			{
			  "ok": false,
			  "error": "invalid_auth"
			}
		EOF
	)
	run handle_slack_api_error "$response" "test_context"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Authentication failed"
	echo "$output" | grep -q "SLACK_BOT_USER_OAUTH_TOKEN"
	echo "$output" | grep -q "test_context"
}

@test "handle_slack_api_error:: handles channel_not_found error" {
	local response=$(
		cat <<-'EOF'
			{
			  "ok": false,
			  "error": "channel_not_found"
			}
		EOF
	)
	run handle_slack_api_error "$response" "test_context"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Channel not found"
	echo "$output" | grep -q "test_context"
}

@test "handle_slack_api_error:: handles not_in_channel error" {
	local response=$(
		cat <<-'EOF'
			{
			  "ok": false,
			  "error": "not_in_channel"
			}
		EOF
	)
	run handle_slack_api_error "$response" "test_context"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Bot is not in the specified channel"
	echo "$output" | grep -q "Invite the bot"
}

@test "handle_slack_api_error:: handles missing_scope error with needed scope" {
	local response=$(
		cat <<-'EOF'
			{
			  "ok": false,
			  "error": "missing_scope",
			  "needed": "channels:read"
			}
		EOF
	)
	run handle_slack_api_error "$response" "test_context"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Missing required OAuth scope"
	echo "$output" | grep -q "channels:read"
}

@test "handle_slack_api_error:: handles unknown error" {
	local response=$(
		cat <<-'EOF'
			{
			  "ok": false,
			  "error": "unknown_error"
			}
		EOF
	)
	run handle_slack_api_error "$response" "test_context"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Slack API error: unknown_error"
	echo "$output" | grep -q "test_context"
}

@test "handle_slack_api_error:: works without context" {
	local response=$(
		cat <<-'EOF'
			{
			  "ok": false,
			  "error": "rate_limited"
			}
		EOF
	)
	run handle_slack_api_error "$response"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Rate limited"
	[[ "$output" != *"Context:"* ]]
}

########################################################
