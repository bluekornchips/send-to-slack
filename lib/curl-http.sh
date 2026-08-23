#!/usr/bin/env bash
#
# Shared curl HTTP body/status parsing for Slack helpers
#

# Split curl output captured with -w "\n%{http_code}" into body and status.
#
# Arguments:
#   $1 - curl_output: full curl stdout (body + trailing http code line)
#
# Side Effects:
# - Sets CURL_HTTP_BODY and CURL_HTTP_CODE
#
# Returns:
# - 0 always
_parse_curl_http_response() {
	local curl_output="$1"

	CURL_HTTP_CODE=$(sed -n '$p' <<<"$curl_output")
	CURL_HTTP_BODY=$(sed '$d' <<<"$curl_output")

	export CURL_HTTP_CODE CURL_HTTP_BODY

	return 0
}
