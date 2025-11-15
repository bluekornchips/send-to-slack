#!/usr/bin/env bash
#
# Send to Slack script
# Processes JSON payload from stdin and sends message to Slack channel via API
# Supports Block Kit formatting, file uploads, and attachments
#
set -eo pipefail

########################################################
# Default values
########################################################
SLACK_API_URL="https://slack.com/api/chat.postMessage"
SHOW_METADATA="false"
SHOW_PAYLOAD="false"
METADATA="[]"

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
			'{
        "metadata": [
          { "name": "dry_run", "value": $dry_run },
          { "name": "show_metadata", "value": $show_metadata },
          { "name": "show_payload", "value": $show_payload }
        ]
      }'
	)

	if [[ "${SHOW_PAYLOAD}" == "true" ]] && [[ -n "${payload}" ]]; then
		local safe_payload
		# Redact token if source field exists, otherwise use payload as-is
		if jq -e '.source' <<<"${payload}" >/dev/null 2>&1; then
			safe_payload=$(jq '.source.slack_bot_user_oauth_token = "[REDACTED]"' <<<"${payload}")
		else
			safe_payload="${payload}"
		fi
		METADATA=$(echo "$METADATA" | jq \
			--arg payload "$safe_payload" \
			'.metadata += [{"name": "payload", "value": $payload}]')
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
		echo "get_message_permalink:: Slack API returned error:" >&2
		jq -r '.' <<<"${api_response}" >&2
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
		temp_payload=$(mktemp /tmp/crosspost-payload.XXXXXX)
		echo "$crosspost_payload" >"$temp_payload"

		# Parse the payload
		local parsed_payload
		if ! parsed_payload=$(parse_payload "$temp_payload"); then
			echo "crosspost_notification:: failed to parse payload for channel $channel" >&2
			rm -f "$temp_payload"
			continue
		fi

		rm -f "$temp_payload"

		# Send the notification
		if ! send_notification "$parsed_payload"; then
			echo "crosspost_notification:: failed to send notification to channel $channel" >&2
			continue
		fi
	done

	return 0
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

	local response
	if ! response=$(curl -X POST "${SLACK_API_URL}" \
		-H "Authorization: Bearer ${SLACK_BOT_USER_OAUTH_TOKEN}" \
		-H "Content-type: application/json; charset=utf-8" \
		-d "${payload}" \
		--silent --show-error \
		--max-time 30 \
		--connect-timeout 10); then
		echo "send_notification:: curl failed to send request" >&2
		return 1
	fi

	# Check if Slack API returned success
	if ! echo "${response}" | jq -e '.ok' >/dev/null 2>&1; then
		echo "send_notification:: Slack API returned error:" >&2
		jq -r '.' <<<"${response}" >&2
		return 1
	fi

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

# Process input from stdin or file specified via -file|--file option
#
# Inputs:
# - $@: Command line arguments (may include -file|--file <path>)
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
		-file | --file)
			if [[ -n "${input_file}" ]]; then
				echo "process_input:: -file|--file option can only be specified once" >&2
				return 1
			fi
			if [[ $# -lt 2 ]]; then
				echo "process_input:: -file|--file requires a file path argument" >&2
				return 1
			fi
			input_file="$2"
			shift 2
			;;
		*)
			echo "process_input:: unknown option: $1" >&2
			echo "process_input:: use -file|--file <path> to specify input file, or provide input via stdin" >&2
			return 1
			;;
		esac
	done

	# Only one of stdin or file is allowed
	if [[ -n "${input_file}" ]]; then
		# Check if stdin has data being piped in, not just redirected from /dev/null like in a test script
		if [[ ! -t 0 ]]; then
			local stdin_source
			stdin_source=$(readlink -f /proc/self/fd/0 2>/dev/null || echo "")
			# If stdin is not /dev/null and not a terminal, assume it has data
			if [[ -z "$stdin_source" ]] || [[ "$stdin_source" != "/dev/null" ]]; then
				# Try to peek at stdin to see if there's data (this consumes one byte if present)
				local peek_byte
				if peek_byte=$(dd bs=1 count=1 iflag=nonblock 2>/dev/null); then
					if [[ -n "$peek_byte" ]]; then
						echo "process_input:: cannot use both -file|--file option and stdin input" >&2
						echo "process_input:: please provide input via either stdin or -file|--file, not both" >&2
						return 1
					fi
				fi
			fi
		fi
		if [[ ! -f "${input_file}" ]]; then
			echo "process_input:: input file does not exist: ${input_file}" >&2
			return 1
		fi
		if [[ ! -r "${input_file}" ]]; then
			echo "process_input:: input file is not readable: ${input_file}" >&2
			return 1
		fi
		if [[ ! -s "${input_file}" ]]; then
			echo "process_input:: input file is empty: ${input_file}" >&2
			return 1
		fi
		use_stdin="false"
	else
		if [[ -t 0 ]]; then
			echo "process_input:: no input provided: use -file|--file <path> or provide input via stdin" >&2
			return 1
		fi
		use_stdin="true"
	fi

	input_payload=$(mktemp /tmp/resource-in.XXXXXX)
	chmod 0600 "${input_payload}"

	# Read from stdin or file and write to temp file
	if [[ "${use_stdin}" == "true" ]]; then
		cat >"${input_payload}"
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
		cp "${input_file}" "${input_payload}"
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

# Main entry point that processes stdin payload and sends to Slack
#
# Inputs:
# - Reads JSON payload from stdin or from file specified with -file|--file
# - Command line arguments: -file|--file <path> (optional)
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
	local script_dir
	local bin_dir
	local main_args

	main_args=("$@")

	if [[ -z "${SEND_TO_SLACK_ROOT}" ]]; then
		local script_path
		script_path=$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")
		script_dir=$(dirname "$script_path")

		# Check for source/Docker layout: script_dir/bin exists
		if [[ -d "$script_dir/bin" ]] && [[ -f "$script_dir/bin/parse-payload.sh" ]]; then
			SEND_TO_SLACK_ROOT="$script_dir"
			bin_dir="$script_dir/bin"
		# Check for installed layout: helper scripts are in same directory as script
		# In this case, SEND_TO_SLACK_ROOT should be parent so bin/blocks paths resolve correctly
		elif [[ -f "$script_dir/parse-payload.sh" ]] && [[ -d "$script_dir/blocks" ]]; then
			SEND_TO_SLACK_ROOT=$(dirname "$script_dir")
			bin_dir="$script_dir"
		else
			echo "main:: cannot locate bin directory. Script location: $script_dir" >&2
			return 1
		fi
	fi

	# Determine bin_dir if SEND_TO_SLACK_ROOT was set externally
	if [[ -z "${bin_dir}" ]]; then
		if [[ -d "${SEND_TO_SLACK_ROOT}/bin" ]] && [[ -f "${SEND_TO_SLACK_ROOT}/bin/parse-payload.sh" ]]; then
			bin_dir="${SEND_TO_SLACK_ROOT}/bin"
		elif [[ -f "${SEND_TO_SLACK_ROOT}/bin/parse-payload.sh" ]] && [[ -d "${SEND_TO_SLACK_ROOT}/bin/blocks" ]]; then
			bin_dir="${SEND_TO_SLACK_ROOT}/bin"
		else
			echo "main:: cannot locate parse-payload.sh in ${SEND_TO_SLACK_ROOT}" >&2
			return 1
		fi
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

	trap 'rm -f "$input_payload"' EXIT

	timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

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
	parsed_payload_file=$(mktemp /tmp/parsed-payload.XXXXXX)
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
		echo "${json_output}" >"${SEND_TO_SLACK_OUTPUT}"
		echo "main:: output written to ${SEND_TO_SLACK_OUTPUT}"
	else
		echo "${json_output}"
	fi

	echo "main:: finished running send-to-slack.sh successfully"

	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
