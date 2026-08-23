#!/usr/bin/env bash
#
# Shared setup for lib/slack/api Bats suites
#

api_test_setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		fail "Failed to get git root"
	fi

	# shellcheck source=lib/bootstrap.sh
	source "${GIT_ROOT}/lib/bootstrap.sh"

	SCRIPT="${GIT_ROOT}/lib/slack/api.sh"
	if [[ ! -f "$SCRIPT" ]]; then
		fail "Script not found: $SCRIPT"
	fi

	export GIT_ROOT
	export SCRIPT
}

api_test_setup() {
	# shellcheck source=lib/bootstrap.sh
	source "${GIT_ROOT}/lib/bootstrap.sh"
	# shellcheck source=lib/slack/api.sh
	source "$SCRIPT"

	SLACK_BOT_USER_OAUTH_TOKEN="test-token"
	DRY_RUN="true"
	RETRY_INITIAL_DELAY=1
	RETRY_MAX_ATTEMPTS=3
	RETRY_MAX_DELAY=60
	RETRY_BACKOFF_MULTIPLIER=2
	DELIVERY_METHOD="api"

	_SLACK_WORKSPACE=$(mktemp -d \
		"${BATS_TEST_TMPDIR}/slack-api-tests.workspace.XXXXXX")
	export _SLACK_WORKSPACE

	export SLACK_BOT_USER_OAUTH_TOKEN
	export DRY_RUN
	export RETRY_INITIAL_DELAY
	export RETRY_MAX_ATTEMPTS
	export RETRY_MAX_DELAY
	export RETRY_BACKOFF_MULTIPLIER
	export DELIVERY_METHOD
}

api_test_teardown() {
	[[ -n "${_SLACK_WORKSPACE:-}" ]] && rm -rf "$_SLACK_WORKSPACE"
	[[ -n "${attempt_file:-}" ]] && rm -f "$attempt_file"
	[[ -n "${sleep_log:-}" ]] && rm -f "$sleep_log"
	[[ -n "${url_capture:-}" ]] && rm -f "$url_capture"
}

mock_curl_failure() {
	curl() {
		printf '%s\n' '{"ok": false, "error": "invalid_auth"}'
		printf '%s\n' '200'
		return 0
	}

	export -f curl
}

mock_curl_permalink_success() {
	curl() {
		if [[ "$*" == *"chat.getPermalink"* ]]; then
			printf '%s\n' '{"ok": true, "permalink": "https://workspace.slack.com/archives/C123456/p1234567890123456"}'
			printf '%s\n' '200'
			return 0
		fi
		printf '%s\n' '{"ok": true, "channel": "C123456", "ts": "1234567890.123456"}'
		printf '%s\n' '200'
		return 0
	}

	export -f curl
}

mock_curl_permalink_failure() {
	curl() {
		if [[ "$*" == *"chat.getPermalink"* ]]; then
			printf '%s\n' '{"ok": false, "error": "channel_not_found"}'
			printf '%s\n' '200'
			return 0
		fi
		printf '%s\n' '{"ok": true, "channel": "C123456", "ts": "1234567890.123456"}'
		printf '%s\n' '200'
		return 0
	}

	export -f curl
}
