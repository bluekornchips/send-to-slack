#!/usr/bin/env bash
#
# send_notification: deliver a payload via Web API or Incoming Webhook
# Loaded by lib/slack/api.sh
# Depends on: http.sh _execute_slack_delivery, file-upload.sh share_uploaded_files
#

# One delivery attempt for send_notification. File payloads share via
# files.completeUploadExternal. Other payloads use chat.postMessage or webhook.
#
# Arguments:
#   $1 - payload_file: temp file with the JSON payload
#   $2 - payload: JSON payload string
#
# Side Effects:
# - POSTs to Slack via share_uploaded_files, chat.postMessage, or webhook
#
# Returns:
#   0 on success
#   1 on delivery failure
_send_notification_attempt() {
	local payload_file="$1"
	local payload="$2"

	echo "send_notification:: delivering message using method" \
		"${DELIVERY_METHOD}" >&2

	if jq -e '.files | type == "array" and length > 0' >/dev/null 2>&1 \
		<<<"$payload"; then
		if [[ "$DELIVERY_METHOD" != "api" ]]; then
			echo "send_notification:: file uploads require API delivery" >&2
			return 1
		fi

		if ! share_uploaded_files "$payload"; then
			return 1
		fi

		return 0
	fi

	if [[ "$DELIVERY_METHOD" == "api" ]]; then
		if ! _send_by_api "$payload_file" "$payload"; then
			return 1
		fi

		return 0
	fi

	if ! _send_by_webhook "$payload_file"; then
		return 1
	fi

	return 0
}

# Send notification via Slack API token or Incoming Webhook URL
#
# Arguments:
#   $1 - payload: JSON payload to send
#
# Side Effects:
# - Sends HTTP POST request to Slack API or webhook URL
# - Outputs success or error messages to stdout/stderr
# - Updates RESPONSE and optional NOTIFICATION_PERMALINK globals
#
# Returns:
# - 0 on successful message delivery or dry run
# - 1 on configuration or delivery failures
send_notification() {
	local payload="$1"

	if [[ "${DRY_RUN}" == "true" ]]; then
		echo "send_notification:: DRY_RUN enabled, skipping Slack API call"
		return 0
	fi

	if [[ -z "${DELIVERY_METHOD:-}" ]]; then
		echo "send_notification:: DELIVERY_METHOD is required, parse_payload must" \
			"run before send_notification" >&2
		return 1
	fi

	if [[ -z "${payload}" ]]; then
		echo "send_notification:: payload is required" >&2
		return 1
	fi

	if [[ -n "${EPHEMERAL_USER:-}" ]] \
		&& jq -e '.files | type == "array" and length > 0' >/dev/null 2>&1 \
			<<<"$payload"; then
		echo "send_notification:: file uploads are not supported for ephemeral messages" >&2
		return 1
	fi

	if [[ "$DELIVERY_METHOD" == "api" ]] \
		&& [[ -z "${SLACK_BOT_USER_OAUTH_TOKEN:-}" ]]; then
		echo "send_notification:: SLACK_BOT_USER_OAUTH_TOKEN is required for API" \
			"delivery" >&2
		return 1
	fi

	if [[ "$DELIVERY_METHOD" == "webhook" ]] && [[ -z "${WEBHOOK_URL:-}" ]]; then
		echo "send_notification:: WEBHOOK_URL is required for webhook delivery" >&2
		return 1
	fi

	local fetch_permalink="false"
	if [[ "$DELIVERY_METHOD" == "api" ]]; then
		fetch_permalink="true"
	fi

	_execute_slack_delivery \
		"send_notification" \
		"send_notification.payload" \
		"$payload" \
		"_send_notification_attempt" \
		"send_notification:: message delivered successfully via ${DELIVERY_METHOD}" \
		"$fetch_permalink"
}
