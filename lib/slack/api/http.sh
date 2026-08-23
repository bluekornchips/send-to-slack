#!/usr/bin/env bash
# shellcheck source=lib/slack/api/errors.sh
# shellcheck source=lib/slack/api/permalink.sh
# shellcheck source=lib/slack/api/retry.sh
#
# Slack HTTP transport for Web API methods and Incoming Webhooks
# Loaded by lib/slack/api.sh
# Depends on: config.sh constants, errors.sh helpers, retry.sh
#

# Split curl output captured with -w "\n%{http_code}" into body and status.
#
# Arguments:
#   $1 - curl_output: full curl stdout (body + trailing http code line)
#
# Side Effects:
# - Sets SLACK_HTTP_BODY and SLACK_HTTP_CODE
#
# Returns:
# - 0 always
_parse_curl_http_response() {
	local curl_output="$1"
	SLACK_HTTP_CODE=$(sed -n '$p' <<<"$curl_output")
	SLACK_HTTP_BODY=$(sed '$d' <<<"$curl_output")
	export SLACK_HTTP_CODE SLACK_HTTP_BODY
	return 0
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
# - Sets SLACK_LAST_RESPONSE with API response body
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
	SLACK_LAST_RESPONSE="${SLACK_HTTP_BODY}"
	export SLACK_LAST_RESPONSE

	if [[ "$SLACK_HTTP_CODE" != "200" ]]; then
		echo "${log_prefix}:: HTTP error code: $SLACK_HTTP_CODE" >&2
		return 1
	fi

	if ! echo "$SLACK_LAST_RESPONSE" | jq . >/dev/null 2>&1; then
		echo "${log_prefix}:: Invalid JSON response from Slack API" >&2
		return 1
	fi

	if ! echo "$SLACK_LAST_RESPONSE" | jq -e '.ok == true' >/dev/null 2>&1; then
		local error_code
		error_code=$(echo "$SLACK_LAST_RESPONSE" \
			| jq -r '.error // "unknown"' 2>/dev/null)
		# shellcheck source=lib/slack/api/errors.sh
		if _is_error_in_list "$error_code" "${ERROR_CODES_TRUE_FAILURES[@]}"; then
			# shellcheck source=lib/slack/api/errors.sh
			handle_slack_api_error "$SLACK_LAST_RESPONSE" "$log_prefix"
			echo "${log_prefix}:: Full request payload:" >&2
			jq . <<<"$payload" >&2
			return 2
		fi
		return 1
	fi

	return 0
}

# POST form-encoded fields to a Slack Web API method URL
#
# Arguments:
#   $1 - api_url: full Slack API method URL
#   $2 - log_prefix: prefix for stderr messages
#   $3+ - form fields passed to curl --data-urlencode
#
# Side Effects:
# - Sets SLACK_LAST_RESPONSE with API response body
#
# Returns:
# - 0 on success
# - 1 on failure
_slack_api_form_post() {
	local api_url="$1"
	local log_prefix="$2"
	shift 2

	local curl_output
	local -a encode_args=()
	local field

	for field in "$@"; do
		encode_args+=(--data-urlencode "$field")
	done

	curl_output=$(curl -X POST "${api_url}" \
		-H "Authorization: Bearer ${SLACK_BOT_USER_OAUTH_TOKEN}" \
		"${encode_args[@]}" \
		--silent --show-error \
		--max-time 30 \
		--connect-timeout 10 \
		-w "\n%{http_code}" 2>&1)

	_parse_curl_http_response "$curl_output"
	SLACK_LAST_RESPONSE="${SLACK_HTTP_BODY}"
	export SLACK_LAST_RESPONSE

	if [[ "$SLACK_HTTP_CODE" != "200" ]]; then
		echo "${log_prefix}:: HTTP error code: $SLACK_HTTP_CODE" >&2
		return 1
	fi

	if ! echo "$SLACK_LAST_RESPONSE" | jq -e '.ok == true' >/dev/null 2>&1; then
		# shellcheck source=lib/slack/api/errors.sh
		handle_slack_api_error "$SLACK_LAST_RESPONSE" "$log_prefix"
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

	_slack_api_post "${SLACK_API_URL}/${CHAT_UPDATE}" "$payload_file" "$payload" \
		"_send_update_by_api"
}

# Send payload using Slack Incoming Webhook URL
#
# Arguments:
#   $1 - payload_file: file path with JSON payload body
#
# Side Effects:
# - Sets SLACK_LAST_RESPONSE with webhook response body
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
	SLACK_LAST_RESPONSE="${SLACK_HTTP_BODY}"
	export SLACK_LAST_RESPONSE

	if [[ "$SLACK_HTTP_CODE" =~ ^2[0-9]{2}$ ]]; then
		return 0
	fi

	echo "_send_by_webhook:: webhook HTTP error code: $SLACK_HTTP_CODE" >&2

	return 1
}

# Finalize a successful Slack delivery attempt
#
# Arguments:
#   $1 - log_prefix: prefix for stderr messages
#   $2 - success_message: line written to stdout on success
#   $3 - payload_for_log: JSON string used for verbose logging
#   $4 - fetch_permalink: "true" to call get_message_permalink for API responses
#
# Side Effects:
# - Sets and exports RESPONSE
#
# Returns:
# - 0 always
_finalize_slack_delivery() {
	local log_prefix="$1"
	local success_message="$2"
	local payload_for_log="$3"
	local fetch_permalink="${4:-false}"

	local response="${SLACK_LAST_RESPONSE:-}"
	local channel=""
	local message_ts=""

	if [[ "$fetch_permalink" == "true" ]] && [[ -n "$response" ]] \
		&& jq . >/dev/null 2>&1 <<<"$response"; then
		channel=$(echo "${response}" | jq -r '.channel // empty')
		message_ts=$(echo "${response}" | jq -r '.ts // empty')
		if [[ -n "$channel" ]] && [[ -n "$message_ts" ]] \
			&& [[ "$channel" != "null" ]] \
			&& [[ "$message_ts" != "null" ]]; then
			# shellcheck source=lib/slack/api/permalink.sh
			get_message_permalink "${channel}" "${message_ts}"
		fi
	fi

	echo "$success_message"

	if [[ "${LOG_VERBOSE:-}" == "true" ]]; then
		local block_count
		local sanitized_payload
		block_count=$(echo "$payload_for_log" | jq '.blocks | length // 0' \
			2>/dev/null || echo "0")
		sanitized_payload=$(
			echo "$payload_for_log" \
				| jq 'del(.thread_ts) | .blocks |= (if type == "array" then [.[] \
					{type: .type}] else . end)' \
					2>/dev/null || echo "$payload_for_log" | jq . 2>/dev/null
		)
		cat <<EOF >&2
${log_prefix}:: channel: ${channel}
${log_prefix}:: ts: ${message_ts}
${log_prefix}:: blocks: ${block_count}
${log_prefix}:: request payload (sanitized):
${sanitized_payload}
EOF
	fi

	RESPONSE="$response"
	export RESPONSE

	return 0
}

# Execute a Slack delivery with retries and shared response handling
#
# Arguments:
#   $1 - log_prefix: prefix for stderr messages
#   $2 - temp_prefix: mktemp name prefix under _SLACK_WORKSPACE
#   $3 - payload: JSON payload string
#   $4 - attempt_command: function name invoked for each attempt
#   $5 - success_message: line written to stdout on success
#   $6 - fetch_permalink: "true" to resolve permalink after API delivery
#
# Returns:
# - 0 on success
# - 1 on failure
_execute_slack_delivery() {
	local log_prefix="$1"
	local temp_prefix="$2"
	local payload="$3"
	local attempt_command="$4"
	local success_message="$5"
	local fetch_permalink="${6:-false}"

	local payload_file
	payload_file=$(mktemp "${_SLACK_WORKSPACE}/${temp_prefix}.XXXXXX")
	printf '%s' "$payload" >"$payload_file"

	_delivery_attempt() {
		"$attempt_command" "$payload_file" "$payload"
	}

	local retry_status=0
	# shellcheck source=lib/slack/api/retry.sh
	retry_with_backoff "$RETRY_MAX_ATTEMPTS" _delivery_attempt || retry_status=$?
	rm -f "$payload_file"

	if [[ "$retry_status" -ne 0 ]]; then
		if [[ "$retry_status" -ne 2 ]]; then
			echo "${log_prefix}:: Failed after $RETRY_MAX_ATTEMPTS attempts" >&2
			echo "${log_prefix}:: Full request payload:" >&2
			jq . <<<"$payload" >&2
		fi
		return 1
	fi

	_finalize_slack_delivery "$log_prefix" "$success_message" "$payload" \
		"$fetch_permalink"

	return 0
}
