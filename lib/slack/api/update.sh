#!/usr/bin/env bash
#
# chat.update helpers
# Loaded by lib/slack/api.sh
# Depends on: http.sh _execute_slack_delivery
#

# One chat.update attempt for update_message.
#
# Arguments:
#   $1 - payload_file: temp file with the JSON body
#   $2 - payload: JSON body string
#
# Returns:
#   0 on success
#   1 on retryable failure
#   2 on permanent API failure
_update_message_attempt() {
	local payload_file="$1"
	local payload="$2"

	echo "update_message:: chat.update attempt" >&2
	_send_update_by_api "$payload_file" "$payload"
}

# Update an existing Slack message via chat.update
#
# Arguments:
#   $1 - channel: Channel ID where the message lives
#   $2 - message_ts: Timestamp of the message to update
# $3 - payload: Parsed JSON body, blocks or text, same shape as chat.postMessage
# body
#
# Side Effects:
# - Sends HTTP POST to chat.update
# - Sets RESPONSE to API response body on success
#
# Returns:
# - 0 on success or dry run
# - 1 on failure
update_message() {
	local channel="$1"
	local message_ts="$2"
	local payload="$3"
	local update_body

	if [[ "${DRY_RUN}" == "true" ]]; then
		echo "update_message:: DRY_RUN enabled, skipping Slack chat.update API call"
		return 0
	fi

	if [[ -z "${DELIVERY_METHOD:-}" ]]; then
		echo "update_message:: DELIVERY_METHOD is required, parse_payload must run" \
			"before update_message" >&2
		return 1
	fi

	if [[ "$DELIVERY_METHOD" != "api" ]]; then
		echo "update_message:: chat.update requires API delivery, not webhook" >&2
		return 1
	fi

	if [[ -z "${SLACK_BOT_USER_OAUTH_TOKEN:-}" ]]; then
		echo "update_message:: SLACK_BOT_USER_OAUTH_TOKEN is required" >&2
		return 1
	fi

	if [[ -z "$channel" ]]; then
		echo "update_message:: channel is required" >&2
		return 1
	fi

	if [[ -z "$message_ts" ]]; then
		echo "update_message:: message_ts is required" >&2
		return 1
	fi

	if [[ -z "$payload" ]]; then
		echo "update_message:: payload is required" >&2
		return 1
	fi

	if jq -e '.files | type == "array" and length > 0' >/dev/null 2>&1 \
		<<<"$payload"; then
		echo "update_message:: file uploads are not supported when updating a message" >&2
		return 1
	fi

	if ! update_body=$(echo "$payload" | jq \
		--arg ch "$channel" \
		--arg ts "$message_ts" \
		'del(.thread_ts, .username, .icon_emoji, .icon_url) | .channel = $ch | .ts = $ts' 2>/dev/null); then
		echo "update_message:: failed to build chat.update JSON body" >&2
		return 1
	fi

	_execute_slack_delivery \
		"update_message" \
		"update_message.payload" \
		"$update_body" \
		"_update_message_attempt" \
		"update_message:: message updated successfully" \
		"true"
}
