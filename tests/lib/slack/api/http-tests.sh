#!/usr/bin/env bats
#
# Tests for lib/slack/api/http.sh
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

# _parse_curl_http_response
########################################################

@test "_parse_curl_http_response:: splits body and http code" {
	local curl_output
	curl_output=$(printf '%s\n%s' '{"ok":true}' '200')

	_parse_curl_http_response "$curl_output"
	[[ "$SLACK_HTTP_CODE" == "200" ]]
	[[ "$SLACK_HTTP_BODY" == '{"ok":true}' ]]
}

########################################################
