#!/usr/bin/env bats
#
# Tests for lib/slack/api/update.sh
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
			printf '%s\n' '200'
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
	got_ts=$(echo "${RESPONSE:-}" | jq -r '.ts')
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
			printf '%s\n' '200'
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

########################################################
