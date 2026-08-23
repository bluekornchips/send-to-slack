#!/usr/bin/env bash
# chat.getPermalink helper
# Loaded by lib/slack/api.sh
# Depends on: http.sh transport helpers
#

# Get message permalink from Slack API
#
# Arguments:
#   $1 - channel: Channel ID where the message was posted
#   $2 - message_ts: Message timestamp from chat.postMessage response
#
# Side Effects:
#   Exports NOTIFICATION_PERMALINK if permalink is found
#
# Returns:
#   0 if permalink is found and exported
#   1 if API call fails or permalink is not found
get_message_permalink() {
	local channel="$1"
	local message_ts="$2"

	if [[ -z "$channel" ]]; then
		echo "get_message_permalink:: channel is required" >&2
		return 1
	fi

	if [[ -z "$message_ts" ]]; then
		echo "get_message_permalink:: message_ts is required" >&2
		return 1
	fi

	if [[ -z "${SLACK_BOT_USER_OAUTH_TOKEN}" ]]; then
		echo "get_message_permalink:: SLACK_BOT_USER_OAUTH_TOKEN is required" >&2
		return 1
	fi

	echo "get_message_permalink:: fetching permalink from Slack API" \
		"(channel=${channel} ts=${message_ts})" >&2

	# shellcheck source=lib/slack/api/http.sh
	if ! _slack_api_form_post \
		"${SLACK_API_URL}/${CHAT_GET_PERMALINK}" "get_message_permalink" \
		"channel=${channel}" "message_ts=${message_ts}"; then
		return 1
	fi

	local permalink
	permalink=$(echo "${SLACK_LAST_RESPONSE}" | jq -r '.permalink // empty')

	if [[ -z "$permalink" ]] || [[ "$permalink" == "null" ]]; then
		echo "get_message_permalink:: permalink not found in API response" >&2
		return 1
	fi

	NOTIFICATION_PERMALINK="$permalink"
	export NOTIFICATION_PERMALINK

	echo "get_message_permalink:: permalink extracted: ${NOTIFICATION_PERMALINK}"

	return 0
}
