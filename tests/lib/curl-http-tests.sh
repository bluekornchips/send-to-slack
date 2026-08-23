#!/usr/bin/env bats
#
# Tests for lib/curl-http.sh
#

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		fail "Failed to get git root"
	fi

	LIB="$GIT_ROOT/lib/curl-http.sh"
	if [[ ! -f "$LIB" ]]; then
		fail "Script not found: $LIB"
	fi

	export GIT_ROOT
	export LIB

	return 0
}

setup() {
	source "$LIB"
	unset CURL_HTTP_BODY CURL_HTTP_CODE

	return 0
}

@test "_parse_curl_http_response:: splits body and http code" {
	local curl_output
	curl_output=$(printf '%s\n%s' '{"ok":true}' '200')

	_parse_curl_http_response "$curl_output"
	[[ "$CURL_HTTP_CODE" == "200" ]]
	[[ "$CURL_HTTP_BODY" == '{"ok":true}' ]]
}

@test "_parse_curl_http_response:: preserves multiline JSON body" {
	local curl_output
	curl_output=$(printf '%s\n%s\n%s\n%s' '{' '  "ok": true' '}' '200')

	_parse_curl_http_response "$curl_output"
	[[ "$CURL_HTTP_CODE" == "200" ]]
	[[ "$CURL_HTTP_BODY" == $'{\n  "ok": true\n}' ]]
	jq -e '.ok == true' <<<"$CURL_HTTP_BODY" >/dev/null
}

@test "_parse_curl_http_response:: handles empty body with status line" {
	local curl_output
	curl_output=$(printf '\n%s' '204')

	_parse_curl_http_response "$curl_output"
	[[ "$CURL_HTTP_CODE" == "204" ]]
	[[ -z "$CURL_HTTP_BODY" ]]
}

@test "_parse_curl_http_response:: exports CURL_HTTP_BODY and CURL_HTTP_CODE" {
	local curl_output
	curl_output=$(printf '%s\n%s' 'ok' '201')

	_parse_curl_http_response "$curl_output"

	# Subshell sees exported values
	bash -c '[[ "$CURL_HTTP_CODE" == "201" && "$CURL_HTTP_BODY" == "ok" ]]'
}
