#!/usr/bin/env bash
#
# Slack Web API and Incoming Webhook delivery helpers
# Used by send-to-slack.sh, crosspost.sh, replies.sh
#

########################################################
# API endpoints and retry policy
########################################################
SLACK_API_URL="https://slack.com/api"
CHAT_POST_MESSAGE="chat.postMessage"
CHAT_POST_EPHEMERAL="chat.postEphemeral"
CHAT_UPDATE="chat.update"
CHAT_GET_PERMALINK="chat.getPermalink"

RETRY_MAX_ATTEMPTS=3
RETRY_INITIAL_DELAY=1
RETRY_MAX_DELAY=60
RETRY_BACKOFF_MULTIPLIER=2

ERROR_CODES_TRUE_FAILURES=(
	"invalid_auth"
	"channel_not_found"
	"not_in_channel"
	"user_not_in_channel"
	"missing_scope"
	"invalid_blocks"
	"invalid_attachments"
	"message_not_found"
	"cant_update_message")

# Check if error code is in the given list. Used for retry vs fail branching.
#
# Inputs:
# - $1 - code: error code string to look up
# - $2 ... - list of error code strings
#
# Returns:
# - 0 if code is in the list, 1 otherwise
_is_error_in_list() {
	local code="$1"
	shift
	local elem
	for elem in "$@"; do
		if [[ "$code" == "$elem" ]]; then
			return 0
		fi
	done

	return 1
}

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

########################################################
# Documentation URLs
########################################################
DOC_URL_AUTHENTICATION="https://api.slack.com/authentication"
DOC_URL_BLOCK_KIT_BLOCKS="https://docs.slack.dev/reference/block-kit/blocks"
DOC_URL_CHAT_POSTMESSAGE_ERRORS="https://api.slack.com/methods/chat.postMessage#errors"
DOC_URL_CONVERSATIONS_JOIN="https://api.slack.com/methods/conversations.join"
DOC_URL_CONVERSATIONS_LIST="https://api.slack.com/methods/conversations.list"
DOC_URL_LEGACY_ATTACHMENTS="https://api.slack.com/reference/messaging/payload#legacy"
DOC_URL_RATE_LIMITS="https://api.slack.com/docs/rate-limits"
DOC_URL_SCOPES="https://api.slack.com/scopes"

# Handle Slack API errors with detailed context
#
# Arguments:
#   $1 - response: Slack API response JSON
#   $2 - context: Additional context string
#
# Side Effects:
# - Outputs detailed error messages to stderr
#
# Returns:
# - 0 always
handle_slack_api_error() {
	local response="$1"
	local context="$2"

	local error_code
	error_code=$(echo "$response" | jq -r '.error // "unknown"' 2>/dev/null || echo "unknown")

	case "$error_code" in
	"rate_limited")
		echo "handle_slack_api_error:: Rate limited. Slack API is throttling requests." >&2
		echo "handle_slack_api_error:: Consider implementing retry logic or reducing request frequency." >&2
		echo "handle_slack_api_error:: See: $DOC_URL_RATE_LIMITS" >&2
		;;
	"invalid_auth")
		echo "handle_slack_api_error:: Authentication failed. Check your SLACK_BOT_USER_OAUTH_TOKEN." >&2
		echo "handle_slack_api_error:: Token may be expired or invalid." >&2
		echo "handle_slack_api_error:: See: $DOC_URL_AUTHENTICATION" >&2
		;;
	"channel_not_found")
		echo "handle_slack_api_error:: Channel not found. Verify the channel name/ID exists and the bot has access." >&2
		echo "handle_slack_api_error:: See: $DOC_URL_CONVERSATIONS_LIST" >&2
		;;
	"not_in_channel")
		echo "handle_slack_api_error:: Bot is not in the specified channel. Invite the bot to the channel first." >&2
		echo "handle_slack_api_error:: See: $DOC_URL_CONVERSATIONS_JOIN" >&2
		;;
	"missing_scope")
		echo "handle_slack_api_error:: Missing required OAuth scope. Check your bot's scopes in Slack app settings." >&2
		local needed_scope
		needed_scope=$(echo "$response" | jq -r '.needed // "unknown"' 2>/dev/null)
		if [[ -n "$needed_scope" ]] && [[ "$needed_scope" != "unknown" ]]; then
			echo "handle_slack_api_error:: Required scope: $needed_scope" >&2
			echo "handle_slack_api_error:: See: $DOC_URL_SCOPES" >&2
		fi
		;;
	"invalid_blocks")
		echo "handle_slack_api_error:: Invalid blocks in payload. Check block structure and validation rules." >&2
		echo "handle_slack_api_error:: See: $DOC_URL_BLOCK_KIT_BLOCKS" >&2
		echo "handle_slack_api_error:: Use Block Kit Builder to validate: https://app.slack.com/block-kit-builder" >&2
		;;
	"invalid_attachments")
		echo "handle_slack_api_error:: Invalid attachments in payload. Common issues:" >&2
		echo "handle_slack_api_error:: - Attachment structure must match Slack's format" >&2
		echo "handle_slack_api_error:: - Maximum 20 attachments per message" >&2
		echo "handle_slack_api_error:: See: $DOC_URL_LEGACY_ATTACHMENTS" >&2
		;;
	*)
		echo "handle_slack_api_error:: Slack API error: $error_code" >&2
		echo "handle_slack_api_error:: See: $DOC_URL_CHAT_POSTMESSAGE_ERRORS" >&2
		;;
	esac

	if [[ -n "$context" ]]; then
		echo "handle_slack_api_error:: Context: $context" >&2
	fi

	if [[ -n "$response" ]]; then
		echo "handle_slack_api_error:: Full Slack API response:" >&2
		echo "$response" | jq . >&2 2>/dev/null || echo "$response" >&2
	fi

	return 0
}

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

	echo "get_message_permalink:: fetching permalink from Slack API (channel=${channel} ts=${message_ts})" >&2

	local api_response
	if ! api_response=$(curl -X POST "${SLACK_API_URL}/${CHAT_GET_PERMALINK}" \
		-H "Authorization: Bearer ${SLACK_BOT_USER_OAUTH_TOKEN}" \
		-H "Content-Type: application/x-www-form-urlencoded" \
		--data-urlencode "channel=${channel}" \
		--data-urlencode "message_ts=${message_ts}" \
		--silent --show-error \
		--max-time 30 \
		--connect-timeout 10); then
		echo "get_message_permalink:: curl failed to send request" >&2
		return 1
	fi

	# Check if Slack API returned success
	if ! echo "${api_response}" | jq -e '.ok' >/dev/null 2>&1; then
		handle_slack_api_error "${api_response}" "get_message_permalink"
		return 1
	fi

	local permalink
	permalink=$(echo "${api_response}" | jq -r '.permalink // empty')

	if [[ -z "$permalink" ]] || [[ "$permalink" == "null" ]]; then
		echo "get_message_permalink:: permalink not found in API response" >&2
		return 1
	fi

	NOTIFICATION_PERMALINK="$permalink"
	export NOTIFICATION_PERMALINK

	echo "get_message_permalink:: permalink extracted: ${NOTIFICATION_PERMALINK}"

	return 0
}

# Retry a command with exponential backoff
#
# Exit code 2 from the command is treated as a permanent failure and is not retried.
#
# Arguments:
#   $1 - max_attempts: Maximum number of retry attempts, default: RETRY_MAX_ATTEMPTS
#   $@ - command and arguments to execute, no eval
#
# Returns:
#   0 on success
#   2 on permanent failure (command returned 2)
#   otherwise last non-zero exit code after all retries
retry_with_backoff() {
	local max_attempts="${1:-$RETRY_MAX_ATTEMPTS}"
	shift

	if [[ -z "$max_attempts" ]]; then
		max_attempts="$RETRY_MAX_ATTEMPTS"
	fi

	if [[ $# -eq 0 ]]; then
		echo "retry_with_backoff:: command to execute is required" >&2
		return 1
	fi

	local attempt=1
	local delay="$RETRY_INITIAL_DELAY"
	local last_exit_code=1

	while [[ "$attempt" -le "$max_attempts" ]]; do
		echo "retry_with_backoff:: executing command (attempt ${attempt}/${max_attempts})" >&2

		local cmd_status=0
		"$@" || cmd_status=$?

		if [[ "$cmd_status" -eq 0 ]]; then
			return 0
		fi

		if [[ "$cmd_status" -eq 2 ]]; then
			return 2
		fi

		last_exit_code=$cmd_status

		if [[ "$attempt" -lt "$max_attempts" ]]; then
			echo "retry_with_backoff:: Attempt $attempt failed, retrying in ${delay}s." >&2
			sleep "$delay"

			delay=$((delay * RETRY_BACKOFF_MULTIPLIER))
			if [[ "$delay" -gt "$RETRY_MAX_DELAY" ]]; then
				delay="$RETRY_MAX_DELAY"
			fi

			attempt=$((attempt + 1))
		else
			echo "retry_with_backoff:: All $max_attempts attempts failed" >&2
			return $last_exit_code
		fi
	done

	return $last_exit_code
}

# POST JSON to a Slack Web API method URL
#
# Arguments:
#   $1 - api_url: full Slack API method URL
#   $2 - payload_file: file path with JSON payload body
#   $3 - payload: payload JSON string for error logging
#   $4 - log_prefix: prefix for stderr messages
#
# Side Effects:
# - Sets SEND_NOTIFICATION_RESPONSE with API response body
# - Logs API errors to stderr
#
# Returns:
# - 0 on success
# - 1 on retryable failure
# - 2 on permanent failure
_slack_api_post() {
	local api_url="$1"
	local payload_file="$2"
	local payload="$3"
	local log_prefix="${4:-_slack_api_post}"

	local curl_output
	curl_output=$(curl -X POST "${api_url}" \
		-H "Authorization: Bearer ${SLACK_BOT_USER_OAUTH_TOKEN}" \
		-H "Content-type: application/json; charset=utf-8" \
		-d "@${payload_file}" \
		--silent --show-error \
		--max-time 30 \
		--connect-timeout 10 \
		-w "\n%{http_code}" 2>&1)

	_parse_curl_http_response "$curl_output"
	SEND_NOTIFICATION_RESPONSE="${CURL_HTTP_BODY}"
	export SEND_NOTIFICATION_RESPONSE

	if [[ "$CURL_HTTP_CODE" != "200" ]]; then
		echo "${log_prefix}:: HTTP error code: $CURL_HTTP_CODE" >&2
		return 1
	fi

	if ! echo "$SEND_NOTIFICATION_RESPONSE" | jq . >/dev/null 2>&1; then
		echo "${log_prefix}:: Invalid JSON response from Slack API" >&2
		return 1
	fi

	if ! echo "$SEND_NOTIFICATION_RESPONSE" | jq -e '.ok == true' >/dev/null 2>&1; then
		local error_code
		error_code=$(echo "$SEND_NOTIFICATION_RESPONSE" | jq -r '.error // "unknown"' 2>/dev/null)
		if _is_error_in_list "$error_code" "${ERROR_CODES_TRUE_FAILURES[@]}"; then
			handle_slack_api_error "$SEND_NOTIFICATION_RESPONSE" "$log_prefix"
			echo "${log_prefix}:: Full request payload:" >&2
			jq . <<<"$payload" >&2
			return 2
		fi
		return 1
	fi

	return 0
}

# Send payload using Slack Web API (chat.postMessage or chat.postEphemeral)
#
# Arguments:
#   $1 - payload_file: file path with JSON payload body
#   $2 - payload: payload JSON string for error logging
#
# Returns:
# - 0 on success
# - 1 on retryable failure
# - 2 on permanent failure
_send_by_api() {
	local payload_file="$1"
	local payload="$2"

	local api_url
	api_url="${SLACK_API_URL}/${CHAT_POST_MESSAGE}"
	if [[ -n "${EPHEMERAL_USER:-}" ]]; then
		api_url="${SLACK_API_URL}/${CHAT_POST_EPHEMERAL}"
	fi

	_slack_api_post "$api_url" "$payload_file" "$payload" "_send_by_api"
}

# Send chat.update payload using Slack Web API
#
# Arguments:
#   $1 - payload_file: file path with JSON payload body
#   $2 - payload: payload JSON string for error logging
#
# Returns:
# - 0 on success
# - 1 on retryable failure
# - 2 on permanent failure
_send_update_by_api() {
	local payload_file="$1"
	local payload="$2"

	_slack_api_post "${SLACK_API_URL}/${CHAT_UPDATE}" "$payload_file" "$payload" "_send_update_by_api"
}

# Update an existing Slack message via chat.update
#
# Arguments:
#   $1 - channel: Channel ID where the message lives
#   $2 - message_ts: Timestamp of the message to update
#   $3 - payload: Parsed JSON body, blocks or text, same shape as chat.postMessage body
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

	if [[ "${DRY_RUN}" == "true" ]]; then
		echo "update_message:: DRY_RUN enabled, skipping Slack chat.update API call"
		return 0
	fi

	if [[ -z "${DELIVERY_METHOD:-}" ]]; then
		echo "update_message:: DELIVERY_METHOD is required, parse_payload must run before update_message" >&2
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

	local update_body
	if ! update_body=$(echo "$payload" | jq \
		--arg ch "$channel" \
		--arg ts "$message_ts" \
		'del(.thread_ts, .username, .icon_emoji, .icon_url) | .channel = $ch | .ts = $ts' 2>/dev/null); then
		echo "update_message:: failed to build chat.update JSON body" >&2
		return 1
	fi

	local payload_file
	payload_file=$(mktemp "${_SLACK_WORKSPACE:-/tmp}/update_message.payload.XXXXXX")
	printf '%s' "$update_body" >"$payload_file"

	_update_message_attempt() {
		echo "update_message:: chat.update attempt" >&2
		_send_update_by_api "$payload_file" "$update_body"
	}

	local retry_status=0
	retry_with_backoff "$RETRY_MAX_ATTEMPTS" _update_message_attempt || retry_status=$?
	local response="${SEND_NOTIFICATION_RESPONSE:-}"
	rm -f "$payload_file"

	if [[ "$retry_status" -ne 0 ]]; then
		if [[ "$retry_status" -ne 2 ]]; then
			echo "update_message:: Failed to update message after $RETRY_MAX_ATTEMPTS attempts" >&2
			echo "update_message:: Full request payload:" >&2
			jq . <<<"$update_body" >&2
		fi
		return 1
	fi

	local resp_channel=""
	local resp_ts=""
	if [[ -n "$response" ]] && jq . >/dev/null 2>&1 <<<"$response"; then
		resp_channel=$(echo "${response}" | jq -r '.channel // empty')
		resp_ts=$(echo "${response}" | jq -r '.ts // empty')
		if [[ -n "$resp_channel" ]] && [[ -n "$resp_ts" ]] && [[ "$resp_channel" != "null" ]] && [[ "$resp_ts" != "null" ]]; then
			get_message_permalink "${resp_channel}" "${resp_ts}"
		fi
	fi

	echo "update_message:: message updated successfully"

	if [[ "${LOG_VERBOSE:-}" == "true" ]]; then
		local block_count
		local sanitized_update_body
		block_count=$(echo "$update_body" | jq '.blocks | length // 0' 2>/dev/null || echo "0")
		sanitized_update_body=$(
			echo "$update_body" |
				jq 'del(.thread_ts) | .blocks |= (if type == "array" then [.[] | {type: .type}] else . end)' \
					2>/dev/null || echo "$update_body" | jq . 2>/dev/null
		)
		cat <<EOF >&2
update_message:: channel: ${resp_channel}
update_message:: ts: ${resp_ts}
update_message:: blocks: ${block_count}
update_message:: request payload (sanitized):
${sanitized_update_body}
EOF
	fi

	RESPONSE="$response"
	export RESPONSE

	return 0
}

# Resolve message_ts and run chat.update when params request an update
#
# Inputs:
# - $1 - input_payload: path to raw Concourse-style input JSON
# - $2 - parsed_payload: JSON string from parse_payload
#
# Side Effects:
# - May call update_message and set RESPONSE
#
# Returns:
# - 0 if chat.update completed successfully
# - 1 on validation or API failure
# - 2 if no update was requested, caller should send a new message
run_chat_update_from_input() {
	local input_payload="$1"
	local parsed_payload="$2"
	local update_ts
	local message_ts_file

	update_ts=$(jq -r '.params.message_ts // empty' "${input_payload}")
	message_ts_file=$(jq -r '.params.message_ts_file // empty' "${input_payload}")

	if [[ -z "$update_ts" ]] && [[ -n "$message_ts_file" ]]; then
		if [[ ! -f "$message_ts_file" ]]; then
			echo "run_chat_update_from_input:: params.message_ts_file: file not found: ${message_ts_file}" >&2

			return 1
		fi
		update_ts=$(<"$message_ts_file")
	fi

	if [[ -z "$update_ts" ]]; then
		return 2
	fi

	echo "run_chat_update_from_input:: updating existing Slack message via chat.update"
	local update_channel
	update_channel=$(jq -r '.params.channel // empty' "${input_payload}")

	if [[ -z "$update_channel" || "$update_channel" == "null" ]]; then
		echo "run_chat_update_from_input:: params.channel is required when params.message_ts is set" >&2
		return 1
	fi

	if [[ "${DELIVERY_METHOD:-api}" != "api" ]]; then
		echo "run_chat_update_from_input:: params.message_ts requires API delivery, not webhook" >&2
		return 1
	fi

	local update_channel_resolved
	update_channel_resolved="$update_channel"
	if [[ "${DRY_RUN:-}" != "true" ]]; then
		if ! update_channel_resolved=$(resolve_channel_id "$update_channel"); then
			echo "run_chat_update_from_input:: failed to resolve params.channel for chat.update, channel ID is required" >&2
			return 1
		fi
	fi

	if ! update_message "$update_channel_resolved" "$update_ts" "$parsed_payload"; then
		echo "run_chat_update_from_input:: failed to update Slack message" >&2
		return 1
	fi

	return 0
}

# Send payload using Slack Incoming Webhook URL
#
# Arguments:
#   $1 - payload_file: file path with JSON payload body
#
# Side Effects:
# - Sets SEND_NOTIFICATION_RESPONSE with webhook response body
# - Logs webhook HTTP errors to stderr
#
# Returns:
# - 0 on success
# - 1 on failure
_send_by_webhook() {
	local payload_file="$1"

	local webhook_output
	webhook_output=$(curl -X POST "${WEBHOOK_URL}" \
		-H "Content-type: application/json; charset=utf-8" \
		-d "@${payload_file}" \
		--silent --show-error \
		--max-time 30 \
		--connect-timeout 10 \
		-w "\n%{http_code}" 2>&1)

	_parse_curl_http_response "$webhook_output"
	SEND_NOTIFICATION_RESPONSE="${CURL_HTTP_BODY}"
	export SEND_NOTIFICATION_RESPONSE

	if [[ "$CURL_HTTP_CODE" =~ ^2[0-9]{2}$ ]]; then
		return 0
	fi

	echo "_send_by_webhook:: webhook HTTP error code: $CURL_HTTP_CODE" >&2

	return 1
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
		echo "send_notification:: DELIVERY_METHOD is required, parse_payload must run before send_notification" >&2
		return 1
	fi

	if [[ -z "${payload}" ]]; then
		echo "send_notification:: payload is required" >&2
		return 1
	fi

	if [[ "$DELIVERY_METHOD" == "api" ]] && [[ -z "${SLACK_BOT_USER_OAUTH_TOKEN:-}" ]]; then
		echo "send_notification:: SLACK_BOT_USER_OAUTH_TOKEN is required for API delivery" >&2
		return 1
	fi

	if [[ "$DELIVERY_METHOD" == "webhook" ]] && [[ -z "${WEBHOOK_URL:-}" ]]; then
		echo "send_notification:: WEBHOOK_URL is required for webhook delivery" >&2
		return 1
	fi

	local payload_file
	payload_file=$(mktemp "$_SLACK_WORKSPACE/send_notification.payload.XXXXXX")
	printf '%s' "$payload" >"$payload_file"

	_send_notification_attempt() {
		echo "send_notification:: delivering message using method ${DELIVERY_METHOD}" >&2
		if [[ "$DELIVERY_METHOD" == "api" ]]; then
			_send_by_api "$payload_file" "$payload"
		else
			_send_by_webhook "$payload_file"
		fi
	}

	local retry_status=0
	retry_with_backoff "$RETRY_MAX_ATTEMPTS" _send_notification_attempt || retry_status=$?
	local response="${SEND_NOTIFICATION_RESPONSE:-}"
	rm -f "$payload_file"

	if [[ "$retry_status" -ne 0 ]]; then
		if [[ "$retry_status" -ne 2 ]]; then
			echo "send_notification:: Failed to send notification after $RETRY_MAX_ATTEMPTS attempts" >&2
			echo "send_notification:: Full request payload:" >&2
			jq . <<<"$payload" >&2
		fi
		return 1
	fi

	# Extract channel and timestamp from API response for permalink support
	local channel=""
	local message_ts=""
	if [[ "$DELIVERY_METHOD" == "api" ]] && [[ -n "$response" ]] && jq . >/dev/null 2>&1 <<<"$response"; then
		channel=$(echo "${response}" | jq -r '.channel // empty')
		message_ts=$(echo "${response}" | jq -r '.ts // empty')
		if [[ -n "$channel" ]] && [[ -n "$message_ts" ]] && [[ "$channel" != "null" ]] && [[ "$message_ts" != "null" ]]; then
			get_message_permalink "${channel}" "${message_ts}"
		fi
	fi

	echo "send_notification:: message delivered successfully via ${DELIVERY_METHOD}"

	if [[ "${LOG_VERBOSE:-}" == "true" ]]; then
		local block_count
		local sanitized_payload
		block_count=$(echo "$payload" | jq '.blocks | length // 0' 2>/dev/null || echo "0")
		sanitized_payload=$(
			echo "$payload" |
				jq 'del(.thread_ts) | .blocks |= (if type == "array" then [.[] | {type: .type}] else . end)' \
					2>/dev/null || echo "$payload" | jq . 2>/dev/null
		)
		cat <<EOF >&2
send_notification:: channel: ${channel}
send_notification:: ts: ${message_ts}
send_notification:: blocks: ${block_count}
send_notification:: request payload (sanitized):
${sanitized_payload}
EOF
	fi

	RESPONSE="$response"
	export RESPONSE

	return 0
}
