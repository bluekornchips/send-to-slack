#!/usr/bin/env bash
#
# Send to Slack script
# Processes JSON payload from stdin and sends message to Slack channel via API
# Supports Block Kit formatting, file uploads, and attachments
#
set -eo pipefail
umask 077

########################################################
# Default values
########################################################
SLACK_API_URL="https://slack.com/api/chat.postMessage"
SHOW_METADATA="true"
SHOW_PAYLOAD="true"
METADATA="[]"

RETRY_MAX_ATTEMPTS=3
RETRY_INITIAL_DELAY=1
RETRY_MAX_DELAY=60
RETRY_BACKOFF_MULTIPLIER=2

ERROR_CODES_TRUE_FAILURES=(
	"invalid_auth"
	"channel_not_found"
	"not_in_channel"
	"missing_scope"
	"invalid_blocks"
	"invalid_attachments")
ERROR_CODES_RETRYABLE=("rate_limited")

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

# Display usage information
#
# Side Effects:
# - Outputs usage message to stdout
#
# Returns:
# - 0 always
usage() {
	cat <<EOF
Usage: send-to-slack [OPTIONS]

Send messages to Slack using Block Kit formatting.

OPTIONS:
  -f, --file <path>     Read payload from file instead of stdin
  -v, --version         Display version information and exit
  -h, --help            Display this help message and exit
  --health-check        Validate dependencies and Slack API connectivity without sending

For more information, see: https://github.com/bluekornchips/send-to-slack
EOF
	return 0
}

# Resolve version from known locations
#
# Inputs:
# - $1 - root_path: Base directory for repository or installation
#
# Outputs:
# - Writes version string to stdout on success
#
# Returns:
# - 0 on success, 1 on missing
get_version() {
	local root_path="$1"
	local candidates
	local version_path
	local version_value

	if [[ -z "$root_path" ]]; then
		return 1
	fi

	candidates=("${root_path}/VERSION")

	for version_path in "${candidates[@]}"; do
		if [[ -f "$version_path" ]]; then
			version_value=$(tr -d '\r' <"$version_path" | tr -d '\n')
			if [[ -n "$version_value" ]]; then
				echo "$version_value"
				return 0
			fi
		fi
	done

	return 1
}

# Resolve commit from git metadata when available
#
# Inputs:
# - $1 - root_path: Base directory for repository or installation
#
# Outputs:
# - Writes commit string to stdout on success
#
# Returns:
# - 0 on success, 1 on missing
get_commit() {
	local root_path="$1"
	local commit_value

	if [[ -z "$root_path" ]]; then
		return 1
	fi

	if command -v git >/dev/null 2>&1 && [[ -d "${root_path}/.git" ]]; then
		if commit_value=$(git -C "$root_path" rev-parse --short HEAD 2>/dev/null); then
			if [[ -n "$commit_value" ]]; then
				echo "$commit_value"
				return 0
			fi
		fi
	fi

	return 1
}

# Print version information for CLI output
#
# Inputs:
# - $1 - root_path: Base directory for repository or installation
#
# Outputs:
# - Writes version info to stdout
#
# Returns:
# - 0 always
print_version() {
	local root_path="$1"
	local version
	local commit
	local github_url="https://github.com/bluekornchips/send-to-slack"

	if ! version=$(get_version "$root_path"); then
		version="unknown"
	fi

	if ! commit=$(get_commit "$root_path"); then
		commit="unknown"
	fi

	echo "send-to-slack, (${github_url})"
	echo "version: ${version}"
	echo "commit: ${commit}"

	return 0
}

# Check for required external commands
#
# Returns:
#   0 if all dependencies are available
#   1 if any dependency is missing
check_dependencies() {
	local missing_deps=()
	local required_commands=("jq" "curl")

	for cmd in "${required_commands[@]}"; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			missing_deps+=("$cmd")
		fi
	done

	if [[ ${#missing_deps[@]} -gt 0 ]]; then
		echo "check_dependencies:: missing required dependencies: ${missing_deps[*]}" >&2
		echo "check_dependencies:: please install missing dependencies and try again" >&2
		return 1
	fi

	return 0
}

# Create Concourse metadata output structure
#
# Arguments:
#   $1 - payload: JSON payload to include in metadata (optional, only if SHOW_PAYLOAD is true)
#
# Side Effects:
# - Sets global METADATA variable with Concourse metadata format
#
# Returns:
# - 0 on successful metadata creation
create_metadata() {
	local payload="$1"

	if [[ "${SHOW_METADATA}" != "true" ]]; then
		return 0
	fi

	METADATA=$(
		jq -n \
			--arg dry_run "$DRY_RUN" \
			--arg show_metadata "$SHOW_METADATA" \
			--arg show_payload "$SHOW_PAYLOAD" \
			'[
          { "name": "dry_run", "value": $dry_run },
          { "name": "show_metadata", "value": $show_metadata },
          { "name": "show_payload", "value": $show_payload }
        ]'
	)

	if [[ "${SHOW_PAYLOAD}" == "true" ]] && [[ -n "${payload}" ]]; then
		METADATA=$(echo "$METADATA" | jq \
			--arg payload "${payload}" \
			'. += [{"name": "payload", "value": $payload}]')
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

	local api_response
	if ! api_response=$(curl -X POST "https://slack.com/api/chat.getPermalink" \
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

crosspost_notification() {
	local input_payload="$1"

	local crosspost
	crosspost=$(jq '.params.crosspost // {}' "$input_payload")

	if [[ -z "${crosspost}" ]] || [[ "${crosspost}" == "{}" ]]; then
		echo "crosspost_notification:: crosspost is empty, skipping."
		return 0
	fi

	local channels_json
	local text
	local default_text="This is an automated crosspost."

	channels_json=$(jq '.params.crosspost.channels // []' "$input_payload")
	# Normalize channels: accept a single string or an array
	channels_json=$(echo "${channels_json}" | jq 'if type == "string" then [.] elif type == "array" then . else [] end')
	text=$(jq -r '.params.crosspost.text // ""' "$input_payload")

	if [[ -z "${channels_json}" ]] || [[ "${channels_json}" == "[]" ]]; then
		echo "crosspost_notification:: channels not set, skipping."
		return 0
	fi

	if [[ -z "${text}" ]]; then
		text="${default_text}"
	fi

	# Create a structured rich text block with proper link element format
	# Text and permalink are on separate lines using separate rich_text_section elements
	local rich_text_block
	rich_text_block=$(jq -n \
		--arg text "$text" \
		--arg permalink "$NOTIFICATION_PERMALINK" \
		'
			{
				"type": "rich_text",
				"elements": [
					{
						"type": "rich_text_section",
						"elements": [
							{
								"type": "text",
								"text": $text
							}
						]
					},
					{
						"type": "rich_text_section",
						"elements": [
							{
								"type": "link",
								"url": $permalink
							}
						]
					}
				]
			}
		')

	# Get source from original payload for crosspost payloads
	local source_json
	source_json=$(jq '.source // {}' "$input_payload")

	# Process each channel
	local channel_count
	channel_count=$(jq '. | length' <<<"${channels_json}")
	for ((i = 0; i < channel_count; i++)); do
		local channel
		channel=$(jq -r ".[$i]" <<<"${channels_json}")

		# Create a full payload for this channel
		local crosspost_payload
		crosspost_payload=$(jq -n \
			--argjson source "$source_json" \
			--arg channel "$channel" \
			--argjson rich_text_block "$rich_text_block" \
			'{
				"source": $source,
				"params": {
					"channel": $channel,
					"blocks": [
						{
							"rich-text": $rich_text_block
						}
					]
				}
			}')

		# Write payload to temp file for parsing
		local temp_payload
		temp_payload=$(mktemp /tmp/send-to-slack.crosspost-payload.XXXXXX)
		if ! chmod 700 "$temp_payload"; then
			echo "crosspost_notification:: failed to secure temp payload ${temp_payload}" >&2
			rm -f "$temp_payload"
			return 1
		fi
		trap 'rm -f "$temp_payload"' RETURN EXIT ERR
		echo "$crosspost_payload" >"$temp_payload"

		# Parse the payload
		local parsed_payload
		if ! parsed_payload=$(parse_payload "$temp_payload"); then
			echo "crosspost_notification:: failed to parse payload for channel $channel" >&2
			rm -f "$temp_payload"
			trap - RETURN EXIT ERR
			continue
		fi

		rm -f "$temp_payload"
		trap - RETURN EXIT ERR

		# Send the notification
		if ! send_notification "$parsed_payload"; then
			echo "crosspost_notification:: failed to send notification to channel $channel" >&2
			continue
		fi
	done

	return 0
}

# Handle Slack API errors with detailed context
#
# Arguments:
#   $1 - response: Slack API response JSON
#   $2 - context: Additional context string
#
# Side Effects:
# - Outputs detailed error messages to stderr
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
		if [[ -n "$context" ]]; then
			echo "handle_slack_api_error:: Context: $context" >&2
		fi
		;;
	"invalid_auth")
		echo "handle_slack_api_error:: Authentication failed. Check your SLACK_BOT_USER_OAUTH_TOKEN." >&2
		echo "handle_slack_api_error:: Token may be expired or invalid." >&2
		echo "handle_slack_api_error:: See: $DOC_URL_AUTHENTICATION" >&2
		if [[ -n "$context" ]]; then
			echo "handle_slack_api_error:: Context: $context" >&2
		fi
		;;
	"channel_not_found")
		echo "handle_slack_api_error:: Channel not found. Verify the channel name/ID exists and the bot has access." >&2
		echo "handle_slack_api_error:: See: $DOC_URL_CONVERSATIONS_LIST" >&2
		if [[ -n "$context" ]]; then
			echo "handle_slack_api_error:: Context: $context" >&2
		fi
		;;
	"not_in_channel")
		echo "handle_slack_api_error:: Bot is not in the specified channel. Invite the bot to the channel first." >&2
		echo "handle_slack_api_error:: See: $DOC_URL_CONVERSATIONS_JOIN" >&2
		if [[ -n "$context" ]]; then
			echo "handle_slack_api_error:: Context: $context" >&2
		fi
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
		if [[ -n "$context" ]]; then
			echo "handle_slack_api_error:: Context: $context" >&2
		fi
		;;
	"invalid_attachments")
		echo "handle_slack_api_error:: Invalid attachments in payload. Common issues:" >&2
		echo "handle_slack_api_error:: - Attachment structure must match Slack's format" >&2
		echo "handle_slack_api_error:: - Maximum 20 attachments per message" >&2
		echo "handle_slack_api_error:: See: $DOC_URL_LEGACY_ATTACHMENTS" >&2
		if [[ -n "$context" ]]; then
			echo "handle_slack_api_error:: Context: $context" >&2
		fi
		;;
	*)
		echo "handle_slack_api_error:: Slack API error: $error_code" >&2
		echo "handle_slack_api_error:: See: $DOC_URL_CHAT_POSTMESSAGE_ERRORS" >&2
		if [[ -n "$context" ]]; then
			echo "handle_slack_api_error:: Context: $context" >&2
		fi
		;;
	esac

	if [[ -n "$response" ]]; then
		echo "handle_slack_api_error:: Full Slack API response:" >&2
		echo "$response" | jq . >&2 2>/dev/null || echo "$response" >&2
	fi
}

# Retry a command with exponential backoff
#
# Arguments:
#   $1 - max_attempts: Maximum number of retry attempts (default: RETRY_MAX_ATTEMPTS)
#   $@ - command and arguments to execute (no eval)
#
# Returns:
#   0 on success
#   1 on failure after all retries
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

	while [[ $attempt -le $max_attempts ]]; do
		# Execute the command and capture exit code
		local cmd_status=0
		"$@" || cmd_status=$?

		if [[ $cmd_status -eq 0 ]]; then
			return 0
		fi

		last_exit_code=$cmd_status

		# Check if we should retry
		if [[ $attempt -lt $max_attempts ]]; then
			echo "retry_with_backoff:: Attempt $attempt failed, retrying in ${delay}s." >&2
			sleep "$delay"

			delay=$((delay * RETRY_BACKOFF_MULTIPLIER))
			if [[ $delay -gt $RETRY_MAX_DELAY ]]; then
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

# Health check function
#
# Checks dependencies and optionally Slack API connectivity
#
# Returns:
#   0 if all checks pass
#   1 if any check fails
health_check() {
	local errors=0

	echo "health_check:: Starting health check."

	# Check dependencies
	if ! command -v jq >/dev/null 2>&1; then
		echo "health_check:: jq not found in PATH" >&2
		errors=$((errors + 1))
	else
		echo "health_check:: jq found: $(command -v jq)"
	fi

	if ! command -v curl >/dev/null 2>&1; then
		echo "health_check:: curl not found in PATH" >&2
		errors=$((errors + 1))
	else
		echo "health_check:: curl found: $(command -v curl)"
	fi

	# Check Slack API connectivity if token is provided
	if [[ -n "${SLACK_BOT_USER_OAUTH_TOKEN}" ]]; then
		echo "health_check:: Testing Slack API connectivity."
		if [[ "${DRY_RUN}" == "true" || "${SKIP_SLACK_API_CHECK}" == "true" ]]; then
			echo "health_check:: Slack API connectivity check skipped (DRY_RUN or SKIP_SLACK_API_CHECK set)"
		else
			local response
			local http_code
			http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
				-H "Authorization: Bearer ${SLACK_BOT_USER_OAUTH_TOKEN}" \
				--max-time 5 \
				--connect-timeout 5 \
				"https://slack.com/api/auth.test" 2>/dev/null)

			if [[ "$http_code" == "200" ]]; then
				response=$(curl -s -X POST \
					-H "Authorization: Bearer ${SLACK_BOT_USER_OAUTH_TOKEN}" \
					--max-time 5 \
					--connect-timeout 5 \
					"https://slack.com/api/auth.test" 2>/dev/null)

				if echo "$response" | jq -e '.ok == true' >/dev/null 2>&1; then
					local team
					local user
					team=$(echo "$response" | jq -r '.team // "unknown"' 2>/dev/null)
					user=$(echo "$response" | jq -r '.user // "unknown"' 2>/dev/null)
					echo "health_check:: Slack API accessible - Team: $team, User: $user"
				else
					local error
					error=$(echo "$response" | jq -r '.error // "unknown"' 2>/dev/null)
					echo "health_check:: Slack API authentication failed: $error" >&2
					if [[ "$error" != "invalid_auth" ]]; then
						errors=$((errors + 1))
					fi
				fi
			else
				echo "health_check:: Slack API not accessible (HTTP $http_code)" >&2
				errors=$((errors + 1))
			fi
		fi
	else
		echo "health_check:: SLACK_BOT_USER_OAUTH_TOKEN not set, skipping API connectivity check"
	fi

	if [[ $errors -eq 0 ]]; then
		echo "health_check:: Health check passed"
		return 0
	else
		echo "health_check:: Health check failed with $errors error(s)" >&2
		return 1
	fi
}

# Send notification to Slack API
#
# Arguments:
#   $1 - payload: JSON payload to send to Slack API
#
# Side Effects:
# - Sends HTTP POST request to Slack API
# - Outputs success or error messages to stdout/stderr
# - Exports NOTIFICATION_PERMALINK if successful
#
# Returns:
# - 0 on successful message delivery
# - 1 if dry run is enabled, token/payload missing, or API call fails
send_notification() {
	local payload="$1"

	if [[ "${DRY_RUN}" == "true" ]]; then
		echo "send_notification:: DRY_RUN enabled, skipping Slack API call"
		return 0
	fi

	if [[ -z "${SLACK_BOT_USER_OAUTH_TOKEN}" ]]; then
		echo "send_notification:: SLACK_BOT_USER_OAUTH_TOKEN is required" >&2
		return 1
	fi

	if [[ -z "${payload}" ]]; then
		echo "send_notification:: payload is required" >&2
		return 1
	fi

	# Use retry logic for the API call
	local response=""
	local attempt=1
	local delay="$RETRY_INITIAL_DELAY"
	local last_exit_code=0

	while [[ $attempt -le $RETRY_MAX_ATTEMPTS ]]; do
		# Make the API call
		local curl_output
		curl_output=$(curl -X POST "${SLACK_API_URL}" \
			-H "Authorization: Bearer ${SLACK_BOT_USER_OAUTH_TOKEN}" \
			-H "Content-type: application/json; charset=utf-8" \
			-d "${payload}" \
			--silent --show-error \
			--max-time 30 \
			--connect-timeout 10 \
			-w "\n%{http_code}" 2>&1)

		local http_code
		http_code=$(echo "$curl_output" | tail -n1)
		response=$(echo "$curl_output" | sed '$d')

		# Check for HTTP errors
		if [[ "$http_code" != "200" ]]; then
			echo "send_notification:: HTTP error code: $http_code" >&2
			if [[ -n "$response" ]]; then
				echo "send_notification:: HTTP response body:" >&2
				echo "$response" | jq . >&2 2>/dev/null || echo "$response" >&2
			fi
			last_exit_code=1
		# response is valid JSON
		elif ! echo "$response" | jq . >/dev/null 2>&1; then
			echo "send_notification:: Invalid JSON response from Slack API" >&2
			echo "send_notification:: Raw response:" >&2
			echo "$response" >&2
			last_exit_code=1
		# Slack API returned success
		elif ! echo "$response" | jq -e '.ok == true' >/dev/null 2>&1; then
			local error_code
			error_code=$(echo "$response" | jq -r '.error // "unknown"' 2>/dev/null)

			#error retryable or not
			case "$error_code" in
			"${ERROR_CODES_RETRYABLE[@]}")
				echo "send_notification:: Rate limited, will retry" >&2
				last_exit_code=1
				;;
			"${ERROR_CODES_TRUE_FAILURES[@]}")
				# fail immediately
				handle_slack_api_error "$response" "send_notification"
				echo "send_notification:: Full request payload:" >&2
				jq . <<<"$payload" >&2
				return 1
				;;
			*)
				#retrys okay
				echo "send_notification:: Slack API error: $error_code, will retry" >&2
				echo "send_notification:: Error response:" >&2
				echo "$response" | jq . >&2 2>/dev/null || echo "$response" >&2
				last_exit_code=1
				;;
			esac
		else
			break
		fi

		if [[ $attempt -lt $RETRY_MAX_ATTEMPTS ]] && [[ $last_exit_code -ne 0 ]]; then
			echo "send_notification:: Attempt $attempt failed, retrying in ${delay}s." >&2
			sleep "$delay"

			delay=$((delay * RETRY_BACKOFF_MULTIPLIER))
			if [[ $delay -gt $RETRY_MAX_DELAY ]]; then
				delay="$RETRY_MAX_DELAY"
			fi

			attempt=$((attempt + 1))
		else
			if [[ -n "$response" ]]; then
				handle_slack_api_error "$response" "send_notification"
			else
				echo "send_notification:: Failed to send notification after $RETRY_MAX_ATTEMPTS attempts" >&2
				echo "send_notification:: No response received from Slack API" >&2
			fi
			echo "send_notification:: Full request payload:" >&2
			jq . <<<"$payload" >&2
			return 1
		fi
	done

	# Extract channel and timestamp from response to get permalink
	local channel
	local message_ts
	channel=$(echo "${response}" | jq -r '.channel // empty')
	message_ts=$(echo "${response}" | jq -r '.ts // empty')

	if [[ -n "$channel" ]] && [[ -n "$message_ts" ]] && [[ "$channel" != "null" ]] && [[ "$message_ts" != "null" ]]; then
		get_message_permalink "${channel}" "${message_ts}"
	fi

	echo "send_notification:: message delivered to Slack successfully"

	RESPONSE="$response"
	export RESPONSE

	return 0
}

# Process input from stdin or file specified via -f|--file option
#
# Inputs:
# - $@: Command line arguments (may include -f|--file <path>)
#
# Outputs:
# - Writes path to temporary input payload file to stdout on success
#
# Side Effects:
# - Creates temporary file for input payload
# - Outputs error messages to stderr
#
# Returns:
# - 0 on successful input processing
# - 1 if argument parsing, validation, or input reading fails
process_input() {
	local input_file
	local use_stdin
	local input_payload

	input_file=""
	use_stdin="false"

	# Parse command line arguments
	while [[ $# -gt 0 ]]; do
		case $1 in
		-f | -file | --file)
			if [[ -n "${input_file}" ]]; then
				echo "process_input:: -f|-file|--file option can only be specified once" >&2
				return 1
			fi
			if [[ $# -lt 2 ]]; then
				echo "process_input:: -f|-file|--file requires a file path argument" >&2
				return 1
			fi
			input_file="$2"
			shift 2
			;;
		*)
			echo "process_input:: unknown option: $1" >&2
			echo "process_input:: use -f|-file|--file <path> to specify input file, or provide input via stdin" >&2
			return 1
			;;
		esac
	done

	# Use file if specified, otherwise use stdin
	if [[ -n "${input_file}" ]]; then
		if [[ ! -f "${input_file}" ]]; then
			echo "process_input:: input file does not exist: ${input_file}" >&2
			return 1
		fi
		use_stdin="false"
	else
		if [[ -t 0 ]]; then
			echo "process_input:: no input provided: use -f|--file <path> or provide input via stdin" >&2
			return 1
		fi
		use_stdin="true"
	fi

	input_payload=$(mktemp /tmp/send-to-slack.resource-in.XXXXXX)
	if ! chmod 700 "$input_payload"; then
		echo "process_input:: failed to secure temp input ${input_payload}" >&2
		rm -f "$input_payload"
		return 1
	fi

	# Read from stdin or file and write to temp file
	if [[ "${use_stdin}" == "true" ]]; then
		if ! cat >"${input_payload}"; then
			echo "process_input:: failed to read from stdin" >&2
			rm -f "${input_payload}"
			return 1
		fi
		if [[ ! -f "${input_payload}" ]]; then
			echo "process_input:: input file was not created" >&2
			rm -f "${input_payload}"
			return 1
		fi
		if [[ ! -s "${input_payload}" ]]; then
			echo "process_input:: no input received on stdin" >&2
			rm -f "${input_payload}"
			return 1
		fi
	else
		if ! cat -- "${input_file}" >"${input_payload}"; then
			echo "process_input:: failed to read input file: ${input_file}" >&2
			ls -l "${input_file}" >&2
			rm -f "${input_payload}"
			return 1
		fi
		if [[ ! -f "${input_payload}" ]]; then
			echo "process_input:: failed to copy input file to temp file" >&2
			rm -f "${input_payload}"
			return 1
		fi
		if [[ ! -s "${input_payload}" ]]; then
			echo "process_input:: input file is empty: ${input_file}" >&2
			rm -f "${input_payload}"
			return 1
		fi
	fi

	echo "${input_payload}"

	return 0
}

# Initialize script environment and locate lib directory
#
# Side Effects:
#   Sets SEND_TO_SLACK_ROOT and bin_dir variables
#
# Outputs:
#   Writes bin_dir path to stdout
#
# Returns:
#   0 on success
#   1 if lib directory cannot be located
initialize_script_environment() {
	local script_dir
	local bin_dir

	resolve_path() {
		local p="$1"
		if [[ "$p" != */* ]]; then
			p=$(command -v "$p" 2>/dev/null || echo "$p")
		fi

		local count=0
		while [[ -L "$p" && $count -lt 10 ]]; do
			local target
			target=$(readlink "$p")
			if [[ "$target" == /* ]]; then
				p="$target"
			else
				p="$(cd "$(dirname "$p")" && cd "$(dirname "$target")" && pwd)/$(basename "$target")"
			fi
			count=$((count + 1))
		done
		echo "$p"
	}

	if [[ -z "${SEND_TO_SLACK_ROOT}" ]]; then
		local script_path
		script_path=$(resolve_path "${BASH_SOURCE[0]}")
		if [[ -z "$script_path" ]] || [[ ! -f "$script_path" ]]; then
			echo "initialize_script_environment:: cannot determine script path" >&2
			return 1
		fi

		script_dir=$(cd "$(dirname "$script_path")" && pwd)
		if [[ -z "$script_dir" ]]; then
			echo "initialize_script_environment:: cannot determine script directory" >&2
			return 1
		fi

		SEND_TO_SLACK_ROOT="$script_dir"

		# If we're in a bin/ directory, check if there's a send-to-slack directory in the parent
		if [[ "$(basename "$SEND_TO_SLACK_ROOT")" == "bin" ]]; then
			local parent_dir
			parent_dir=$(dirname "$SEND_TO_SLACK_ROOT")
			if [[ -d "$parent_dir/send-to-slack" ]] && [[ -f "$parent_dir/send-to-slack/send-to-slack" ]] && [[ -d "$parent_dir/send-to-slack/lib" ]]; then
				SEND_TO_SLACK_ROOT="$parent_dir/send-to-slack"
			fi
		fi
	fi

	# Validate that SEND_TO_SLACK_ROOT is set and valid
	if [[ -z "${SEND_TO_SLACK_ROOT}" ]]; then
		echo "initialize_script_environment:: SEND_TO_SLACK_ROOT is not set" >&2
		return 1
	fi

	bin_dir="${SEND_TO_SLACK_ROOT}/lib"

	# Validate bin_dir
	if [[ ! -f "${bin_dir}/parse-payload.sh" ]]; then
		echo "initialize_script_environment:: cannot locate parse-payload.sh (bin_dir: ${bin_dir})" >&2
		return 1
	fi

	echo "$bin_dir"

	return 0
}

# Parse command line arguments
#
# Arguments:
#   $@ - Command line arguments
#
# Side Effects:
#   Sets global main_args array and health_check_mode variable
#   May call print_version and exit
#
# Returns:
#   0 on success
#   2 if version or help was requested
parse_main_args() {
	main_args=()
	health_check_mode=false

	while [[ $# -gt 0 ]]; do
		case $1 in
		-v | --version)
			print_version "${SEND_TO_SLACK_ROOT}"
			return 2
			;;
		-h | --help)
			usage
			return 2
			;;
		--health-check)
			health_check_mode=true
			shift
			;;
		*)
			main_args+=("$1")
			shift
			;;
		esac
	done

	return 0
}

# Main entry point that processes stdin payload and sends to Slack
#
# Inputs:
# - Reads JSON payload from stdin or from file specified with -f|--file
# - Command line arguments: -f|--file <path> (optional)
#
# Side Effects:
# - Sends message to Slack API
# - Outputs informational messages to stdout for logging
# - Outputs only JSON to stdout at the end
# - Sets global environment variables (SEND_TO_SLACK_ROOT, PAYLOAD, etc.)
#
# Returns:
# - 0 on successful message delivery and output generation
# - 1 if payload parsing, metadata creation, or notification sending fails
main() {
	local input_payload
	local timestamp
	local bin_dir
	local parse_result

	if ! bin_dir=$(initialize_script_environment); then
		return 1
	fi

	# Parse arguments
	# If help/version is requested, parse_main_args will output and return 2
	parse_result=0
	parse_main_args "$@" || parse_result=$?

	if [[ $parse_result -eq 2 ]]; then
		# Version or help was requested and already printed
		return 0
	fi

	if [[ $parse_result -ne 0 ]]; then
		echo "main:: failed to parse arguments" >&2
		return 1
	fi

	local version
	if ! version=$(get_version "${SEND_TO_SLACK_ROOT}"); then
		version="unknown"
	fi
	echo "main:: send-to-slack ${version}"

	if [[ "$health_check_mode" == "true" ]]; then
		if ! health_check; then
			return 1
		fi
		return 0
	fi

	export SEND_TO_SLACK_ROOT
	export SEND_TO_SLACK_BIN_DIR="$bin_dir"
	export METADATA
	export SHOW_METADATA
	export SHOW_PAYLOAD

	if ! check_dependencies; then
		return 1
	fi

	echo "main:: starting task to send notification to Slack from Concourse"

	# Process input and get path to temp file
	if ! input_payload=$(process_input "${main_args[@]}"); then
		echo "main:: failed to process input" >&2
		return 1
	fi

	trap 'rm -f "$input_payload" "${parsed_payload_file:-}"' EXIT ERR

	timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

	# Check if params.debug is true and override show_payload/show_metadata
	local debug_enabled
	debug_enabled=$(jq -r '.params.debug // false' "${input_payload}")
	if [[ "$debug_enabled" == "true" ]]; then
		SHOW_METADATA="true"
		SHOW_PAYLOAD="true"
		export SHOW_METADATA
		export SHOW_PAYLOAD
	fi

	echo "main:: parsing payload"

	# Ensure file still exists before parsing
	if [[ ! -f "${input_payload}" ]]; then
		echo "main:: input file disappeared before parsing: ${input_payload}" >&2
		return 1
	fi

	if [[ -f "${SEND_TO_SLACK_BIN_DIR}/parse-payload.sh" ]]; then
		source "${SEND_TO_SLACK_BIN_DIR}/parse-payload.sh"
	else
		echo "main:: cannot locate parse-payload.sh at ${SEND_TO_SLACK_BIN_DIR}/parse-payload.sh" >&2
		return 1
	fi

	local parsed_payload_file
	parsed_payload_file=$(mktemp /tmp/send-to-slack.parsed-payload.XXXXXX)
	if ! chmod 700 "$parsed_payload_file"; then
		echo "main:: failed to secure parsed payload file ${parsed_payload_file}" >&2
		rm -f "${parsed_payload_file}"
		return 1
	fi
	if ! parse_payload "${input_payload}" >"${parsed_payload_file}"; then
		echo "main:: failed to parse payload" >&2
		rm -f "${parsed_payload_file}"
		return 1
	fi
	local parsed_payload
	parsed_payload=$(cat "${parsed_payload_file}")
	rm -f "${parsed_payload_file}"

	# Handle create_thread: send first block as regular message, then remaining blocks in thread
	local create_thread
	create_thread=$(jq -r '.params.create_thread // false' "${input_payload}")
	if [[ "$create_thread" == "true" ]]; then
		local block_count
		block_count=$(echo "$parsed_payload" | jq '.blocks | length')

		if ((block_count > 1)); then
			echo "main:: create_thread is true, sending first block as regular message"

			# Extract first block
			local first_block_payload
			first_block_payload=$(echo "$parsed_payload" | jq '{channel: .channel, blocks: [.blocks[0]]}')

			# Send first block as regular message
			if ! send_notification "$first_block_payload"; then
				echo "main:: failed to send first block message" >&2
				return 1
			fi

			# Get thread_ts from the response
			local thread_ts
			thread_ts=$(echo "$RESPONSE" | jq -r '.ts // empty')

			if [[ -z "$thread_ts" || "$thread_ts" == "null" ]]; then
				echo "main:: failed to get thread_ts from first message response" >&2
				return 1
			fi

			# Modify parsed_payload to include thread_ts and exclude first block (send remaining blocks)
			parsed_payload=$(echo "$parsed_payload" | jq --arg thread_ts "$thread_ts" '. + {thread_ts: $thread_ts} | .blocks = .blocks[1:]')

			echo "main:: sending remaining blocks as thread reply with thread_ts: ${thread_ts}"
		fi
	fi

	echo "main:: sending notification"
	if ! send_notification "$parsed_payload"; then
		echo "main:: failed to send notification" >&2
		return 1
	fi

	if ! crosspost_notification "${input_payload}"; then
		echo "main:: failed to crosspost notification" >&2
		return 1
	fi

	echo "main:: creating Concourse metadata"
	if ! create_metadata "$parsed_payload"; then
		echo "main:: failed to create metadata" >&2
		return 1
	fi

	# Output version JSON for Concourse
	# If SEND_TO_SLACK_OUTPUT is set, write to that file, otherwise write to stdout
	local json_output
	json_output=$(jq -n \
		--arg timestamp "${timestamp}" \
		--argjson metadata "${METADATA}" \
		'{
      version: { timestamp: $timestamp },
      metadata: $metadata
    }')

	if [[ -n "${SEND_TO_SLACK_OUTPUT}" ]]; then
		jq -r '.' <<<"${json_output}" >"${SEND_TO_SLACK_OUTPUT}"
		echo "main:: output written to ${SEND_TO_SLACK_OUTPUT}"
	else
		jq -r '.' <<<"${json_output}"
	fi

	echo "main:: finished running send-to-slack.sh successfully"

	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
