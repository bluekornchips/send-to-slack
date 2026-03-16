#!/usr/bin/env bash
#
# Send to Slack script
# Processes JSON payload from stdin and sends message to Slack channel via API
# Supports Block Kit formatting, file uploads, and attachments
#

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
MAX_PAYLOAD_SIZE=262144

ERROR_CODES_TRUE_FAILURES=(
	"invalid_auth"
	"channel_not_found"
	"not_in_channel"
	"missing_scope"
	"invalid_blocks"
	"invalid_attachments")
ERROR_CODES_RETRYABLE=("rate_limited")

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
# - $1 - root_path: Base directory for repository or packaged copy
#
# Outputs:
# - Writes version string to stdout on success
#
# Returns:
# - 0 on success, 1 on missing
get_version() {
	local root_path="$1"
	local version_path
	local version_value

	if [[ -z "$root_path" ]]; then
		return 1
	fi

	version_path="${root_path}/VERSION"

	if [[ -f "$version_path" ]]; then
		version_value=$(tr -d '\r' <"$version_path" | tr -d '\n')
		if [[ -n "$version_value" ]]; then
			echo "$version_value"
			return 0
		fi
	fi

	return 1
}

# Resolve commit from git metadata when available
#
# Inputs:
# - $1 - root_path: Base directory for repository or packaged copy
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
# - $1 - root_path: Base directory for repository or packaged copy
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

# Get safe payload size threshold to avoid exec argument overflow
#
# Outputs:
#   Writes safe byte limit to stdout
#
# Returns:
#   0 always
_get_safe_payload_size() {
	local arg_max
	arg_max=$(getconf ARG_MAX 2>/dev/null || echo "$MAX_PAYLOAD_SIZE")
	printf '%d' $((arg_max / 4))

	return 0
}

# Create Concourse metadata output structure
#
# Arguments:
#   $1 - payload: JSON payload to include in metadata, optional, only if SHOW_PAYLOAD is true
#
# Side Effects:
# - Sets global METADATA variable with Concourse metadata format
#
# Returns:
# - 0 on successful metadata creation
create_metadata() {
	local payload="$1"
	local payload_for_metadata
	local safe_size

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
		payload_for_metadata="$payload"
		safe_size=$(_get_safe_payload_size)

		if [[ ${#payload_for_metadata} -gt "$safe_size" ]]; then
			local stripped
			if stripped=$(echo "$payload_for_metadata" | jq 'del(.blocks, .attachments)' 2>/dev/null) &&
				[[ ${#stripped} -le "$safe_size" ]]; then
				if ! METADATA=$(echo "$METADATA" | jq \
					--arg payload "$stripped" \
					'. += [{"name": "payload", "value": $payload}, {"name": "payload_note", "value": "blocks and attachments excluded: payload exceeded safe metadata size"}]' \
					2>/dev/null); then
					echo "create_metadata:: failed to append stripped payload to metadata" >&2
					METADATA=$(echo "$METADATA" | jq '. += [{"name": "payload_skipped", "value": "payload too large for metadata"}]')
				fi
			else
				echo "create_metadata:: payload too large even after stripping blocks, skipping payload in metadata" >&2
				METADATA=$(echo "$METADATA" | jq '. += [{"name": "payload_skipped", "value": "payload too large for metadata"}]')
			fi
		else
			if ! METADATA=$(echo "$METADATA" | jq --arg payload "${payload_for_metadata}" '. += [{"name": "payload", "value": $payload}]' 2>/dev/null); then
				echo "create_metadata:: failed to append payload to metadata" >&2
				METADATA=$(echo "$METADATA" | jq '. += [{"name": "payload_skipped", "value": "metadata append failed"}]')
			fi
		fi
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
#   $1 - max_attempts: Maximum number of retry attempts, default: RETRY_MAX_ATTEMPTS
#   $@ - command and arguments to execute, no eval
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

	while [[ "$attempt" -le "$max_attempts" ]]; do
		echo "retry_with_backoff:: executing command (attempt ${attempt}/${max_attempts})" >&2

		# Execute the command and capture exit code
		local cmd_status=0
		"$@" || cmd_status=$?

		if [[ "$cmd_status" -eq 0 ]]; then
			return 0
		fi

		last_exit_code=$cmd_status

		# Check if we should retry
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

	if [[ "$errors" -eq 0 ]]; then
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

	local payload_file
	payload_file=$(mktemp "$_SLACK_WORKSPACE/send_notification.payload.XXXXXX")
	printf '%s' "$payload" >"$payload_file"

	while [[ "$attempt" -le "$RETRY_MAX_ATTEMPTS" ]]; do
		echo "send_notification:: posting message to Slack API (attempt ${attempt}/${RETRY_MAX_ATTEMPTS})" >&2

		# Make the API call
		local curl_output
		curl_output=$(curl -X POST "${SLACK_API_URL}" \
			-H "Authorization: Bearer ${SLACK_BOT_USER_OAUTH_TOKEN}" \
			-H "Content-type: application/json; charset=utf-8" \
			-d "@${payload_file}" \
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

			if _is_error_in_list "$error_code" "${ERROR_CODES_TRUE_FAILURES[@]}"; then
				handle_slack_api_error "$response" "send_notification"
				echo "send_notification:: Full request payload:" >&2
				jq . <<<"$payload" >&2
				return 1
			elif _is_error_in_list "$error_code" "${ERROR_CODES_RETRYABLE[@]}"; then
				echo "send_notification:: Rate limited, will retry" >&2
				last_exit_code=1
			else
				echo "send_notification:: Slack API error: $error_code, will retry" >&2
				echo "send_notification:: Error response:" >&2
				echo "$response" | jq . >&2 2>/dev/null || echo "$response" >&2
				last_exit_code=1
			fi
		else
			break
		fi

		if [[ "$attempt" -lt "$RETRY_MAX_ATTEMPTS" ]] && [[ "$last_exit_code" -ne 0 ]]; then
			echo "send_notification:: Attempt $attempt failed, retrying in ${delay}s." >&2
			sleep "$delay"

			delay=$((delay * RETRY_BACKOFF_MULTIPLIER))
			if [[ "$delay" -gt "$RETRY_MAX_DELAY" ]]; then
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

	if [[ "${LOG_VERBOSE:-}" == "true" ]]; then
		local block_count
		block_count=$(echo "$payload" | jq '.blocks | length // 0')
		cat <<EOF >&2
send_notification:: channel: ${channel}
send_notification:: ts: ${message_ts}
send_notification:: blocks: ${block_count}
send_notification:: request payload (sanitized):
$(echo "$payload" | jq 'del(.thread_ts) | .blocks |= (if type == "array" then [.[] | {type: .type}] else . end)' 2>/dev/null || echo "$payload" | jq . 2>/dev/null)
EOF
	fi

	RESPONSE="$response"
	export RESPONSE

	return 0
}

# Process input from stdin or file specified via -f|--file option
#
# Arguments:
#   $1 - output_file: Path to write the input payload to
#   $@ - remaining arguments: Command line arguments, may include -f|--file <path>
#
# Side Effects:
# - Writes input payload to specified output_file
# - Outputs error messages to stderr
#
# Returns:
# - 0 on successful input processing
# - 1 if argument parsing, validation, or input reading fails
process_input_to_file() {
	local output_file="$1"
	shift

	local input_file=""
	local use_stdin="false"

	# Prepare output file
	if ! touch "${output_file}" && chmod 0600 "${output_file}"; then
		echo "process_input_to_file:: failed to secure output file ${output_file}" >&2
		return 1
	fi

	# Parse command line arguments
	while [[ $# -gt 0 ]]; do
		case $1 in
		-f | -file | --file)
			if [[ -n "${input_file}" ]]; then
				echo "process_input_to_file:: -f|-file|--file option can only be specified once" >&2
				return 1
			fi
			if [[ $# -lt 2 ]]; then
				echo "process_input_to_file:: -f|-file|--file requires a file path argument" >&2
				return 1
			fi
			input_file="$2"
			shift 2
			;;
		*)
			echo "process_input_to_file:: unknown option: $1" >&2
			echo "process_input_to_file:: use -f|-file|--file <path> to specify input file, or provide input via stdin" >&2
			return 1
			;;
		esac
	done

	# Use file if specified, otherwise use stdin
	if [[ -n "${input_file}" ]]; then
		if [[ ! -f "${input_file}" ]]; then
			echo "process_input_to_file:: input file does not exist: ${input_file}" >&2
			return 1
		fi
		use_stdin="false"
	else
		if [[ -t 0 ]]; then
			echo "process_input_to_file:: no input provided: use -f|--file <path> or provide input via stdin" >&2
			return 1
		fi
		use_stdin="true"
	fi

	# Read from stdin or file and write to target file
	echo "process_input_to_file:: reading input into ${output_file}" >&2

	if [[ "${use_stdin}" == "true" ]]; then
		if ! cat >"${output_file}"; then
			echo "process_input_to_file:: failed to read from stdin" >&2
			return 1
		fi
		if [[ ! -s "${output_file}" ]]; then
			echo "process_input_to_file:: no input received on stdin" >&2
			return 1
		fi
	else
		if ! cat -- "${input_file}" >"${output_file}"; then
			echo "process_input_to_file:: failed to read input file: ${input_file}" >&2
			ls -l "${input_file}" >&2
			return 1
		fi
		if [[ ! -s "${output_file}" ]]; then
			echo "process_input_to_file:: input file is empty: ${input_file}" >&2
			return 1
		fi
	fi

	if [[ "${use_stdin}" == "true" ]]; then
		export SEND_TO_SLACK_INPUT_SOURCE="stdin"
	fi

	return 0
}

# Find the root directory of the send-to-slack source bundle
#
# Outputs:
#   Writes root_dir path to stdout
#
# Returns:
#   0 on success
#   1 if root directory cannot be located
find_root_dir() {
	local script_path
	local script_dir
	local parent_dir
	local git_root

	# Get the actual path of the script, resolving symlinks
	script_path="${BASH_SOURCE[0]}"
	if [[ -L "$script_path" ]]; then
		script_path=$(readlink -f "$script_path" 2>/dev/null || readlink "$script_path")
	fi

	script_dir=$(cd "$(dirname "$script_path")" && pwd)
	if [[ -z "$script_dir" ]]; then
		echo "find_root_dir:: cannot determine script directory" >&2
		return 1
	fi

	parent_dir=$(cd "${script_dir}/.." && pwd)
	git_root=$(git -C "$script_dir" rev-parse --show-toplevel 2>/dev/null || true)

	# Prefer installed layout, then repo layout, then git root
	if [[ -f "${script_dir}/lib/parse-payload.sh" ]]; then
		echo "$script_dir"
		return 0
	fi

	if [[ -n "$parent_dir" && -f "${parent_dir}/lib/parse-payload.sh" ]]; then
		echo "$parent_dir"
		return 0
	fi

	if [[ -n "$git_root" && -f "${git_root}/lib/parse-payload.sh" ]]; then
		echo "$git_root"
		return 0
	fi

	echo "find_root_dir:: cannot locate lib/parse-payload.sh (checked: ${script_dir}, ${parent_dir}, ${git_root:-none})" >&2
	return 1
}

# Initialize script environment and locate root directory
#
# Outputs:
#   Writes root_dir path to stdout
#
# Returns:
#   0 on success
#   1 if root directory cannot be located
initialize_script_environment() {
	local root_dir
	local lib_dir

	if ! root_dir=$(find_root_dir); then
		return 1
	fi

	lib_dir="${root_dir}/lib"

	if [[ ! -f "${lib_dir}/parse-payload.sh" ]]; then
		echo "initialize_script_environment:: cannot locate parse-payload.sh (lib_dir: ${lib_dir})" >&2
		return 1
	fi

	echo "$root_dir"

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
			local root_dir
			if ! root_dir=$(find_root_dir); then
				echo "parse_main_args:: cannot determine root directory" >&2
				return 1
			fi
			print_version "$root_dir"
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
# - Command line arguments: -f|--file <path>, optional
#
# Side Effects:
# - Sends message to Slack API
# - Outputs informational messages to stdout for logging
# - Outputs only JSON to stdout at the end
# - Sets global environment variables, PAYLOAD, etc.
#
# Returns:
# - 0 on successful message delivery and output generation
# - 1 if payload parsing, metadata creation, or notification sending fails
main() {
	local input_payload
	local timestamp
	local root_dir
	local parse_result

	if ! root_dir=$(initialize_script_environment); then
		return 1
	fi

	# Parse arguments
	# If help/version is requested, parse_main_args will output and return 2
	parse_result=0
	parse_main_args "$@" || parse_result=$?

	if [[ "$parse_result" -eq 2 ]]; then
		# Version or help was requested and already printed
		return 0
	fi

	if [[ "$parse_result" -ne 0 ]]; then
		echo "main:: failed to parse arguments" >&2
		return 1
	fi

	local version
	if ! version=$(get_version "$root_dir"); then
		version="unknown"
	fi
	echo "main:: send-to-slack ${version}"

	if [[ "$health_check_mode" == "true" ]]; then
		if ! health_check; then
			return 1
		fi
		return 0
	fi

	SEND_TO_SLACK_BIN_DIR="$root_dir"
	export SEND_TO_SLACK_BIN_DIR
	export METADATA
	export SHOW_METADATA
	export SHOW_PAYLOAD

	if ! check_dependencies; then
		return 1
	fi

	echo "main:: starting task to send notification to Slack from Concourse"

	_SLACK_WORKSPACE=$(mktemp -d /tmp/send-to-slack.run.XXXXXX)
	export _SLACK_WORKSPACE
	trap 'rm -rf "$_SLACK_WORKSPACE"' EXIT ERR

	input_payload="${_SLACK_WORKSPACE}/input_payload"

	# Process input and write to the designated file in our temp dir
	if ! process_input_to_file "${input_payload}" "${main_args[@]}"; then
		echo "main:: failed to process input" >&2
		return 1
	fi

	timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

	# Check if params.debug is true and override show_payload/show_metadata
	local debug_enabled
	debug_enabled=$(jq -r '.params.debug // false' "${input_payload}")
	if [[ "$debug_enabled" == "true" ]]; then
		SHOW_METADATA="true"
		SHOW_PAYLOAD="true"
		export SHOW_METADATA
		export SHOW_PAYLOAD
		export LOG_VERBOSE="true"
	fi

	if [[ -n "${SEND_TO_SLACK_INPUT_SOURCE:-}" ]]; then
		echo "main:: input source: ${SEND_TO_SLACK_INPUT_SOURCE}" >&2
	fi

	echo "main:: parsing payload"

	# Ensure file still exists before parsing
	if [[ ! -f "${input_payload}" ]]; then
		echo "main:: input file disappeared before parsing: ${input_payload}" >&2
		return 1
	fi

	if [[ -f "${root_dir}/lib/parse-payload.sh" ]]; then
		source "${root_dir}/lib/parse-payload.sh"
	else
		echo "main:: cannot locate parse-payload.sh at ${root_dir}/lib/parse-payload.sh" >&2
		return 1
	fi

	if [[ -f "${root_dir}/bin/crosspost.sh" ]]; then
		source "${root_dir}/bin/crosspost.sh"
	else
		echo "main:: cannot locate crosspost.sh at ${root_dir}/bin/crosspost.sh" >&2
		return 1
	fi

	if [[ -f "${root_dir}/bin/replies.sh" ]]; then
		source "${root_dir}/bin/replies.sh"
	else
		echo "main:: cannot locate replies.sh at ${root_dir}/bin/replies.sh" >&2
		return 1
	fi

	local parsed_payload_file
	parsed_payload_file="${_SLACK_WORKSPACE}/parsed_payload"
	if ! parse_payload "${input_payload}" >"${parsed_payload_file}"; then
		echo "main:: failed to parse payload" >&2
		return 1
	fi
	local parsed_payload
	parsed_payload=$(cat "${parsed_payload_file}")
	rm -f "${parsed_payload_file}"

	echo "main:: sending notification"
	if ! send_notification "$parsed_payload"; then
		echo "main:: failed to send notification" >&2
		return 1
	fi

	# Capture ts from primary message for use as thread anchor in replies
	local primary_ts
	primary_ts=$(echo "$RESPONSE" | jq -r '.ts // empty')

	# Resolve thread_ts for replies: prefer the one in parsed_payload (thread_ts path),
	# fall back to primary message ts
	local reply_thread_ts
	reply_thread_ts=$(echo "$parsed_payload" | jq -r '.thread_ts // empty')
	if [[ -z "$reply_thread_ts" || "$reply_thread_ts" == "null" ]]; then
		reply_thread_ts="${primary_ts:-}"
	fi

	if ! send_thread_replies "${input_payload}" "$reply_thread_ts" "$parsed_payload"; then
		echo "main:: send_thread_replies encountered failures, continuing" >&2
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
	set -eo pipefail
	umask 077
	main "$@"
	exit $?
fi
