#!/usr/bin/env bash
#
# Parse payload and create blocks/attachments
# Processes input configuration and generates Slack API payload
#
# This script uses Slack's legacy attachments feature for colored blocks and table blocks.
# While attachments are not deprecated, Slack recommends using Block Kit blocks directly.
# Legacy attachments may change in future Slack updates in ways that reduce visibility or utility.
# See: https://api.slack.com/reference/messaging/payload#legacy
#
set -eo pipefail

DANGER_COLOR="#F44336"  # Red
SUCCESS_COLOR="#4CAF50" # Green
WARN_COLOR="#FFC107"    # Yellow

########################################################
# Files
########################################################

RICH_TEXT_BLOCK_FILE="bin/blocks/rich-text.sh"
TABLE_BLOCK_FILE="bin/blocks/table.sh"
SECTION_BLOCK_FILE="bin/blocks/section.sh"
HEADER_BLOCK_FILE="bin/blocks/header.sh"
CONTEXT_BLOCK_FILE="bin/blocks/context.sh"
DIVIDER_BLOCK_FILE="bin/blocks/divider.sh"
MARKDOWN_BLOCK_FILE="bin/blocks/markdown.sh"
ACTIONS_BLOCK_FILE="bin/blocks/actions.sh"
IMAGE_BLOCK_FILE="bin/blocks/image.sh"
VIDEO_BLOCK_FILE="bin/blocks/video.sh"

# Other scripts
FILE_UPLOAD_SCRIPT="bin/file-upload.sh"

DEFAULT_DRY_RUN="false"
MAX_TEXT_LENGTH=40000
MAX_BLOCKS=50
MAX_ATTACHMENTS=20

# Validate that a block script file exists
#
# Arguments:
#   $1 - script_path: Relative path to script from SEND_TO_SLACK_ROOT
#
# Returns:
#   0 if script exists and is executable
#   1 if script is missing or not executable
_validate_block_script() {
	local script_path="$1"
	local full_path="${SEND_TO_SLACK_ROOT}/${script_path}"

	if [[ ! -f "$full_path" ]]; then
		echo "_validate_block_script:: block script not found: $full_path" >&2
		return 1
	fi

	return 0
}

create_block() {
	local block_input="$1"
	local block_type="$2"

	if [[ -z "$block_input" ]]; then
		echo "create_block:: input is required" >&2
		return 1
	fi

	if ! jq . >/dev/null 2>&1 <<<"$block_input"; then
		echo "create_block:: block_input must be valid JSON" >&2
		return 1
	fi

	local block
	local script_path=""

	case "$block_type" in
	"rich-text") script_path="$RICH_TEXT_BLOCK_FILE" ;;
	"table") script_path="$TABLE_BLOCK_FILE" ;;
	"section") script_path="$SECTION_BLOCK_FILE" ;;
	"header") script_path="$HEADER_BLOCK_FILE" ;;
	"context") script_path="$CONTEXT_BLOCK_FILE" ;;
	"divider") script_path="$DIVIDER_BLOCK_FILE" ;;
	"markdown") script_path="$MARKDOWN_BLOCK_FILE" ;;
	"actions") script_path="$ACTIONS_BLOCK_FILE" ;;
	"image") script_path="$IMAGE_BLOCK_FILE" ;;
	"video") script_path="$VIDEO_BLOCK_FILE" ;;
	"file") script_path="$FILE_UPLOAD_SCRIPT" ;;
	*)
		echo "create_block:: unsupported block type: $block_type. Skipping." >&2
		return 0
		;;
	esac

	if ! _validate_block_script "$script_path"; then
		return 1
	fi

	local script_exit_code=0
	block=$("$SEND_TO_SLACK_ROOT/$script_path" <<<"$block_input") || script_exit_code=$?

	if [[ $script_exit_code -ne 0 ]]; then
		echo "create_block:: block script failed with exit code $script_exit_code" >&2
		return 1
	fi

	if [[ -z "$block" ]]; then
		echo "create_block:: block script produced no output" >&2
		return 1
	fi

	if ! jq . >/dev/null 2>&1 <<<"$block"; then
		echo "create_block:: block script output is not valid JSON" >&2
		echo "create_block:: output: $block" >&2
		return 1
	fi

	echo "$block"

	return 0
}

# Convert Slack permalink to thread_ts format if needed
#
# Arguments:
#   $1 - input: thread_ts value (may be permalink URL or timestamp)
#
# Returns:
#   Outputs converted thread_ts to stdout
#   Returns original value if no 16-digit number found
#   0 on success
convert_thread_ts() {
	local input="$1"

	# Check if already in correct format (10 digits . 6 digits)
	if echo "$input" | grep -qE '^[0-9]{10}\.[0-9]{6}$'; then
		echo "$input"
		return 0
	fi

	# Extract 16-digit number and convert
	local timestamp
	timestamp=$(echo "$input" | grep -oE '[0-9]{16}' | head -n1)

	if [[ -n "$timestamp" ]]; then
		# Convert format to insert decimal after 10 digits
		local seconds="${timestamp:0:10}"
		local microseconds="${timestamp:10}"

		echo "${seconds}.${microseconds}"

		return 0
	fi

	echo "$input"

	return 0
}

# Validate that input payload file contains valid JSON
#
# Uses global variable: INPUT_PAYLOAD
#
# Returns:
#   0 if valid JSON
#   1 if invalid JSON
validate_input_payload_json() {
	if [[ ! -f "$INPUT_PAYLOAD" ]]; then
		echo "validate_input_payload_json:: payload file not found: $INPUT_PAYLOAD" >&2
		return 1
	fi

	if [[ ! -s "$INPUT_PAYLOAD" ]]; then
		echo "validate_input_payload_json:: payload file is empty: $INPUT_PAYLOAD" >&2
		return 1
	fi

	if ! jq . "$INPUT_PAYLOAD" >/dev/null 2>&1; then
		local jq_error
		jq_error=$(jq . "$INPUT_PAYLOAD" 2>&1 | head -3)
		cat <<EOF >&2
validate_input_payload_json:: invalid JSON in payload file: ${INPUT_PAYLOAD}
validate_input_payload_json:: jq error: ${jq_error}
EOF
		return 1
	fi

	return 0
}

# Load input payload params conditionally (raw params or from_file)
#
# Uses global variable: INPUT_PAYLOAD (modified in place)
#
# Side Effects:
#   Modifies INPUT_PAYLOAD if raw params or from_file are specified
#
# Returns:
#   0 on success
#   1 if source file not found or invalid JSON
load_input_payload_params() {
	local raw_params
	raw_params=$(jq -r '.params.raw // empty' "$INPUT_PAYLOAD")
	if [[ -n "$raw_params" ]]; then
		echo "parse_payload:: using raw payload" >&2
		if ! echo "$raw_params" | jq . >/dev/null 2>&1; then
			echo "parse_payload:: raw payload is not valid JSON" >&2
			return 1
		fi

		# Parse raw string as JSON and use it directly as params
		local parsed_params
		parsed_params=$(echo "$raw_params" | jq '.')

		local updated_payload
		updated_payload=$(jq --argjson parsed_params "$parsed_params" '.params = $parsed_params' "$INPUT_PAYLOAD")
		echo "$updated_payload" >"$INPUT_PAYLOAD"
	fi

	local source_file_path
	source_file_path=$(jq -r '.params.from_file // empty' "$INPUT_PAYLOAD")
	if [[ -n "$source_file_path" ]]; then
		echo "parse_payload:: using payload from file: $source_file_path" >&2

		if [[ ! -f "$source_file_path" ]]; then
			echo "parse_payload:: payload from file not found: $source_file_path" >&2
			return 1
		fi

		if ! jq . "$source_file_path" >/dev/null 2>&1; then
			echo "parse_payload:: payload file contains invalid JSON: $source_file_path" >&2
			return 1
		fi

		# Read file content and use it directly as params
		local file_params
		file_params=$(jq '.' "$source_file_path")
		local updated_payload
		updated_payload=$(jq --argjson file_params "$file_params" '.params = $file_params' "$INPUT_PAYLOAD")
		echo "$updated_payload" >"$INPUT_PAYLOAD"
	fi

	return 0
}

# Load configuration values from payload and environment variables
#
# Uses global variable: INPUT_PAYLOAD
#
# Side Effects:
#   Exports SLACK_BOT_USER_OAUTH_TOKEN, CHANNEL, DRY_RUN
#
# Returns:
#   0 on success
#   1 if required fields are missing
load_configuration() {
	# Check if 'source' key exists in payload
	local source_exists="false"
	if jq -e '.source' "$INPUT_PAYLOAD" >/dev/null 2>&1; then
		source_exists="true"
	fi

	if [[ "$source_exists" == "true" ]]; then
		SLACK_BOT_USER_OAUTH_TOKEN=$(jq -r '.source.slack_bot_user_oauth_token // empty' "$INPUT_PAYLOAD")
		if [[ -z "$SLACK_BOT_USER_OAUTH_TOKEN" ]]; then
			echo "parse_payload:: slack_bot_user_oauth_token is required in source" >&2
			return 1
		fi
	else
		# Fallback to environment variable if source key doesn't exist
		if [[ -n "${SLACK_BOT_USER_OAUTH_TOKEN:-}" ]]; then
			echo "parse_payload:: Source key not found in payload. Using SLACK_BOT_USER_OAUTH_TOKEN from environment variable."
		else
			echo "parse_payload:: SLACK_BOT_USER_OAUTH_TOKEN is required. Not found in payload source or environment." >&2
			return 1
		fi
	fi

	local env_channel_value="${CHANNEL:-}"
	CHANNEL=$(jq -r '.params.channel // empty' "$INPUT_PAYLOAD")
	if [[ -z "$CHANNEL" ]]; then
		if [[ "$source_exists" == "true" ]]; then
			echo "parse_payload:: params.channel is required" >&2
			return 1
		else
			# Use environment variable if available
			if [[ -n "$env_channel_value" ]]; then
				CHANNEL="$env_channel_value"
				echo "parse_payload:: Source key not found in payload. Using CHANNEL from environment variable."
			else
				echo "parse_payload:: params.channel is required. Not found in payload or environment." >&2
				return 1
			fi
		fi
	fi

	if [[ "$source_exists" == "true" ]]; then
		DRY_RUN=$(jq -r \
			--arg default "$DEFAULT_DRY_RUN" \
			'.params.dry_run // $default' \
			"$INPUT_PAYLOAD")
	else
		# Check params.dry_run first, then fall back to env var
		local params_dry_run
		params_dry_run=$(jq -r '.params.dry_run // empty' "$INPUT_PAYLOAD")
		if [[ -n "$params_dry_run" ]]; then
			DRY_RUN="$params_dry_run"
		else
			# Save env var value before potential assignment
			local env_dry_run_value="${DRY_RUN:-}"
			if [[ -n "$env_dry_run_value" ]]; then
				DRY_RUN="$env_dry_run_value"
				echo "parse_payload:: Source key not found in payload. Using DRY_RUN from environment variable."
			else
				DRY_RUN="$DEFAULT_DRY_RUN"
			fi
		fi
	fi

	export DRY_RUN
	export SLACK_BOT_USER_OAUTH_TOKEN
	export CHANNEL

	return 0
}

# Process blocks array and create Slack payload with blocks and attachments
#
# Uses global variable: INPUT_PAYLOAD
#
# Outputs:
#   Writes complete Slack API payload JSON to stdout
#
# Returns:
#   0 on success
#   1 if block processing fails
process_blocks() {
	local blocks_json
	blocks_json=$(jq -r '.params.blocks // []' "$INPUT_PAYLOAD")
	if [[ "$blocks_json" == "[]" ]]; then
		echo "parse_payload:: params.blocks is required" >&2
		return 1
	fi

	local blocks="[]"
	local attachments="[]"

	while read -r block_entry; do
		local block_type
		local block_value
		local block_color

		block_type=$(jq -r '.key' <<<"$block_entry")
		block_value=$(jq -r '.value' <<<"$block_entry")
		block_color=$(jq -r '.value.color // empty' <<<"$block_entry")

		local is_attachment="false"
		if [[ -n "$block_color" ]] || [[ "$block_type" == "table" ]]; then
			is_attachment="true"
		fi

		local block
		if ! block=$(create_block "$block_value" "$block_type"); then
			echo "parse_payload:: failed to create block type '$block_type': $block_entry" >&2
			return 1
		fi

		if [[ "$is_attachment" == "true" ]]; then
			attachments=$(jq \
				--argjson block "$block" \
				--arg color "$block_color" \
				'. += [{ color: $color, blocks: [$block]}]' <<<"$attachments")
		else
			blocks=$(jq --argjson block "$block" '. += [$block]' <<<"$blocks")
		fi

	done < <(jq -r -c '.[] | to_entries[]' <<<"$blocks_json")

	# Validate block count against Slack's limit of 50 blocks per message
	# Ref: https://docs.slack.dev/reference/block-kit/blocks
	local block_count
	block_count=$(jq '. | length' <<<"$blocks")
	if ((block_count > MAX_BLOCKS)); then
		echo "parse_payload:: block count ($block_count) exceeds Slack's maximum of $MAX_BLOCKS blocks per message" >&2
		return 1
	fi

	# Validate attachment count against Slack's limit of 20 attachments per message
	# Ref: https://api.slack.com/reference/messaging/payload#legacy
	# Note: While not deprecated, legacy attachments may change in future Slack updates
	local attachment_count=0
	if [[ "$attachments" != "[]" ]]; then
		attachment_count=$(jq '. | length' <<<"$attachments")
	fi
	if ((attachment_count > MAX_ATTACHMENTS)); then
		echo "parse_payload:: attachment count ($attachment_count) exceeds Slack's maximum of $MAX_ATTACHMENTS attachments per message" >&2
		return 1
	fi

	# Count blocks in attachments (each attachment can contain blocks)
	local attachment_block_count=0
	if [[ "$attachments" != "[]" ]]; then
		attachment_block_count=$(jq '[.[] | .blocks | length] | add' <<<"$attachments")
	fi
	local total_block_count=$((block_count + attachment_block_count))
	if ((total_block_count > MAX_BLOCKS)); then
		echo "parse_payload:: total block count ($total_block_count) exceeds Slack's maximum of $MAX_BLOCKS blocks per message" >&2
		return 1
	fi

	# Read thread_ts and create_thread from params
	local thread_ts
	local create_thread
	thread_ts=$(jq -r '.params.thread_ts // ""' "$INPUT_PAYLOAD")
	create_thread=$(jq -r '.params.create_thread // false' "$INPUT_PAYLOAD")

	# Convert thread_ts if it's a permalink
	if [[ -n "$thread_ts" && "$thread_ts" != "null" && "$thread_ts" != "empty" ]]; then
		local converted_ts
		converted_ts=$(convert_thread_ts "$thread_ts")
		local convert_thread_ts_exit_code=$?
		if [[ $convert_thread_ts_exit_code -ne 0 ]]; then
			echo "parse_payload:: failed to convert thread_ts from permalink" >&2
			return 1
		fi
		thread_ts="$converted_ts"
	fi

	# Validate mutually exclusive parameters
	if [[ "$create_thread" == "true" ]] && [[ -n "$thread_ts" && "$thread_ts" != "null" && "$thread_ts" != "empty" ]]; then
		echo "parse_payload:: create_thread and thread_ts cannot both be set. Use create_thread to create a new thread or thread_ts to reply to an existing thread." >&2
		return 1
	fi

	# Handle create_thread logic
	if [[ "$create_thread" == "true" ]]; then
		if ((total_block_count <= 1)); then
			echo "parse_payload:: create_thread is true but only one block provided, continuing as normal" >&2
		fi
	fi

	local payload
	payload=$(jq -n \
		--arg channel "$CHANNEL" \
		--argjson blocks "$blocks" \
		--argjson attachments "$attachments" \
		'{ "channel": $channel, "blocks": $blocks, "attachments": $attachments }')

	# Add thread_ts to payload if provided and not empty
	if [[ -n "$thread_ts" && "$thread_ts" != "null" && "$thread_ts" != "empty" ]]; then
		payload=$(jq --arg thread_ts "$thread_ts" '. + {thread_ts: $thread_ts}' <<<"$payload")
	fi

	# Validate message text field if present, max 40,000 characters
	# Ref: https://api.slack.com/changelog/2018-04-truncating-really-long-messages
	local text_field
	text_field=$(jq -r '.params.text // empty' "$INPUT_PAYLOAD")
	if [[ -n "$text_field" && "$text_field" != "null" && "$text_field" != "empty" ]]; then
		local text_length=${#text_field}
		if ((text_length > MAX_TEXT_LENGTH)); then
			echo "parse_payload:: text field length ($text_length) exceeds Slack's maximum of $MAX_TEXT_LENGTH characters" >&2
			return 1
		fi
		# Add text field to payload if provided
		payload=$(jq --arg text "$text_field" '. + {text: $text}' <<<"$payload")
	fi

	echo "$payload"

	return 0
}

# Main function to parse payload and create Slack API payload
#
# Arguments:
#   $1 - payload_file: Path to payload file
#
# Outputs:
#   Writes complete Slack API payload JSON to stdout
#
# Side Effects:
#   Sets global INPUT_PAYLOAD variable
#   Exports SLACK_BOT_USER_OAUTH_TOKEN, CHANNEL, DRY_RUN
#
# Returns:
#   0 on success
#   1 if parsing fails
parse_payload() {
	local payload_file="$1"

	INPUT_PAYLOAD="$payload_file"
	export INPUT_PAYLOAD

	if ! validate_input_payload_json; then
		return 1
	fi

	if ! load_input_payload_params; then
		return 1
	fi

	if ! load_configuration; then
		return 1
	fi

	if ! process_blocks; then
		return 1
	fi

	return 0
}
