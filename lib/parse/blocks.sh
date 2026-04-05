#!/usr/bin/env bash
#
# Block processing, Slack limits, and legacy attachment routing
# Requires lib/parse/payload.sh sourced first for _resolve_from_file_path and convert_thread_ts
#

DANGER_COLOR="#F44336"  # Red
SUCCESS_COLOR="#4CAF50" # Green
WARN_COLOR="#FFC107"    # Yellow

########################################################
# Files
########################################################

RICH_TEXT_BLOCK_FILE="lib/blocks/rich-text.sh"
TABLE_BLOCK_FILE="lib/blocks/table.sh"
SECTION_BLOCK_FILE="lib/blocks/section.sh"
HEADER_BLOCK_FILE="lib/blocks/header.sh"
CONTEXT_BLOCK_FILE="lib/blocks/context.sh"
DIVIDER_BLOCK_FILE="lib/blocks/divider.sh"
MARKDOWN_BLOCK_FILE="lib/blocks/markdown.sh"
ACTIONS_BLOCK_FILE="lib/blocks/actions.sh"
IMAGE_BLOCK_FILE="lib/blocks/image.sh"
VIDEO_BLOCK_FILE="lib/blocks/video.sh"

# Other scripts
FILE_UPLOAD_SCRIPT="lib/file-upload.sh"

MAX_TEXT_LENGTH=40000
MAX_BLOCKS=50
MAX_ATTACHMENTS=20
MAX_BLOCK_INPUT_BYTES=524288 # 512 KiB

########################################################
# Documentation URLs
########################################################
DOC_URL_BLOCK_KIT_ACTIONS="https://docs.slack.dev/reference/block-kit/blocks/actions-block"
DOC_URL_BLOCK_KIT_BLOCKS="https://docs.slack.dev/reference/block-kit/blocks"
DOC_URL_BLOCK_KIT_CONTEXT="https://docs.slack.dev/reference/block-kit/blocks/context-block"
DOC_URL_BLOCK_KIT_HEADER="https://docs.slack.dev/reference/block-kit/blocks/header-block"
DOC_URL_BLOCK_KIT_IMAGE="https://docs.slack.dev/reference/block-kit/blocks/image-block"
DOC_URL_BLOCK_KIT_MARKDOWN="https://docs.slack.dev/reference/block-kit/blocks/markdown-block"
DOC_URL_BLOCK_KIT_RICH_TEXT="https://docs.slack.dev/reference/block-kit/blocks/rich-text-block"
DOC_URL_BLOCK_KIT_SECTION="https://docs.slack.dev/reference/block-kit/blocks/section-block"
DOC_URL_BLOCK_KIT_VIDEO="https://docs.slack.dev/reference/block-kit/blocks/video-block"
DOC_URL_LEGACY_ATTACHMENTS="https://api.slack.com/reference/messaging/payload#legacy"

# Validate block input JSON byte size before dispatching to a block script.
# Catches pathologically large inputs before any subprocess is spawned.
# Uses bash string length as a fast proxy for byte count.
#
# Arguments:
#   $1 - block_value: raw JSON string for the block
#   $2 - block_type: block type name, used in error messages
#   $3 - max_bytes: maximum allowed byte size, defaults to MAX_BLOCK_INPUT_BYTES
#
# Returns:
#   0 if within limit
#   1 if over limit or required arguments are missing
_validate_block_input_size() {
	local block_value="$1"
	local block_type="$2"
	local max_bytes="${3:-${MAX_BLOCK_INPUT_BYTES}}"

	if [[ -z "$block_value" ]]; then
		echo "_validate_block_input_size:: block_value is required" >&2
		return 1
	fi

	if [[ -z "$block_type" ]]; then
		echo "_validate_block_input_size:: block_type is required" >&2
		return 1
	fi

	if [[ -z "$max_bytes" ]]; then
		echo "_validate_block_input_size:: max_bytes is required" >&2
		return 1
	fi

	local byte_count
	byte_count=${#block_value}

	if ((byte_count > max_bytes)); then
		echo "_validate_block_input_size:: '$block_type' block input" \
			"(${byte_count} bytes) exceeds limit of ${max_bytes} bytes" >&2
		return 1
	fi

	return 0
}

# Load a single block from a file for block-level from_file
#
# Arguments:
#   $1 - raw_path: Value from block from_file (may be relative or absolute)
#
# Outputs:
#   Writes block JSON to stdout on success
#   Writes error messages to stderr on failure
#
# Returns:
#   0 if path resolves and file contains valid JSON
#   1 if path is invalid, file not found, or file contains invalid JSON
_load_block_item_from_file() {
	local raw_path="$1"
	local source_file_path
	local block_json

	source_file_path=$(_resolve_from_file_path "$raw_path") || return 1

	if ! jq . "$source_file_path" >/dev/null 2>&1; then
		echo "parse_payload:: block file contains invalid JSON: $source_file_path" >&2
		return 1
	fi

	block_json=$(jq '.' "$source_file_path")
	echo "$block_json"

	return 0
}

# Validate block and attachment counts against Slack limits
#
# Arguments:
#   $1 - blocks_file: path to JSON array file of blocks
#   $2 - attachments_file: path to JSON array file of attachments
#
# Returns:
#   0 when within limits
#   1 when a limit is exceeded
_validate_block_counts() {
	local blocks_file="$1"
	local attachments_file="$2"

	if [[ -z "$blocks_file" ]] || [[ -z "$attachments_file" ]]; then
		echo "_validate_block_counts:: blocks_file and attachments_file are required" >&2
		return 1
	fi

	local block_count
	block_count=$(jq '. | length' "$blocks_file")
	if ((block_count > MAX_BLOCKS)); then
		echo "parse_payload:: block count ($block_count) exceeds Slack's maximum of $MAX_BLOCKS blocks per message" >&2
		echo "parse_payload:: See block limits: $DOC_URL_BLOCK_KIT_BLOCKS" >&2
		return 1
	fi

	local attachment_count
	attachment_count=$(jq '. | length' "$attachments_file")
	if ((attachment_count > MAX_ATTACHMENTS)); then
		echo "parse_payload:: attachment count ($attachment_count) exceeds Slack's maximum of $MAX_ATTACHMENTS attachments per message" >&2
		echo "parse_payload:: See attachment limits: $DOC_URL_LEGACY_ATTACHMENTS" >&2
		return 1
	fi

	local attachment_block_count=0
	if ((attachment_count > 0)); then
		attachment_block_count=$(jq '[.[] | .blocks | length] | add' "$attachments_file")
	fi
	local total_block_count=$((block_count + attachment_block_count))
	if ((total_block_count > MAX_BLOCKS)); then
		echo "parse_payload:: total block count ($total_block_count) exceeds Slack's maximum of $MAX_BLOCKS blocks per message" >&2
		echo "parse_payload:: See block limits: $DOC_URL_BLOCK_KIT_BLOCKS" >&2
		return 1
	fi

	return 0
}

# Validate params.thread.replies structure when present
#
# Arguments:
#   $1 - thread_replies_raw: JSON from .params.thread.replies or empty
#
# Returns:
#   0 when absent, empty, or structurally valid
#   1 when invalid
_validate_thread_replies() {
	local thread_replies_raw="$1"

	if [[ -z "$thread_replies_raw" || "$thread_replies_raw" == "null" ]]; then
		return 0
	fi

	if ! echo "$thread_replies_raw" | jq -e 'type == "array"' >/dev/null 2>&1; then
		echo "parse_payload:: thread.replies must be an array" >&2
		return 1
	fi

	local reply_count
	reply_count=$(echo "$thread_replies_raw" | jq 'length')
	local ri
	local reply_blocks
	for ((ri = 0; ri < reply_count; ri++)); do
		reply_blocks=$(echo "$thread_replies_raw" | jq ".[$ri].blocks // empty")
		if [[ -z "$reply_blocks" || "$reply_blocks" == "null" ]]; then
			echo "parse_payload:: thread.replies[$ri].blocks is required and must be non-empty" >&2
			return 1
		fi

		if ! echo "$reply_blocks" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
			echo "parse_payload:: thread.replies[$ri].blocks is required and must be non-empty" >&2
			return 1
		fi
	done

	return 0
}

# Build Slack API payload JSON from channel, block files, and optional fields
#
# Arguments:
#   $1 - channel: channel id or name
#   $2 - blocks_file: path to JSON array of blocks
#   $3 - attachments_file: path to JSON array of attachments
#   $4 - thread_ts: converted thread timestamp or empty
#   $5 - text_field: params.text value or empty
#   $6 - thread_replies_raw: JSON array string for thread replies or empty
#   $7 - delivery_method: api or webhook, defaults to DELIVERY_METHOD or api
#
# Uses global variables: INPUT_PAYLOAD, EPHEMERAL_USER
#
# Outputs:
#   Writes complete Slack API payload JSON to stdout
#
# Returns:
#   0 on success
#   1 if text length exceeds MAX_TEXT_LENGTH
_build_slack_payload() {
	local channel="$1"
	local blocks_file="$2"
	local attachments_file="$3"
	local thread_ts="$4"
	local text_field="$5"
	local thread_replies_raw="$6"
	local delivery_method="${7:-${DELIVERY_METHOD:-api}}"

	if [[ -z "$channel" && "$delivery_method" != "webhook" ]]; then
		echo "_build_slack_payload:: channel is required" >&2
		return 1
	fi

	if [[ -z "$blocks_file" ]] || [[ -z "$attachments_file" ]]; then
		echo "_build_slack_payload:: blocks_file and attachments_file are required" >&2
		return 1
	fi

	local payload
	if [[ -n "$channel" ]]; then
		payload=$(jq -n \
			--arg channel "$channel" \
			--slurpfile blocks "$blocks_file" \
			--slurpfile attachments "$attachments_file" \
			'{ "channel": $channel, "blocks": $blocks[0], "attachments": $attachments[0] }')
	else
		payload=$(jq -n \
			--slurpfile blocks "$blocks_file" \
			--slurpfile attachments "$attachments_file" \
			'{ "blocks": $blocks[0], "attachments": $attachments[0] }')
	fi

	if [[ -n "${EPHEMERAL_USER:-}" ]]; then
		payload=$(jq --arg user "$EPHEMERAL_USER" '. + {user: $user}' <<<"$payload")
	fi

	if [[ -n "$thread_ts" && "$thread_ts" != "null" && "$thread_ts" != "empty" ]]; then
		payload=$(jq --arg thread_ts "$thread_ts" '. + {thread_ts: $thread_ts}' <<<"$payload")
	fi

	if [[ -n "$thread_replies_raw" && "$thread_replies_raw" != "null" ]]; then
		local thread_replies_len
		thread_replies_len=$(echo "$thread_replies_raw" | jq 'length')
		if ((thread_replies_len > 0)); then
			payload=$(jq --argjson replies "$thread_replies_raw" '. + {thread_replies: $replies}' <<<"$payload")
		fi
	fi

	if [[ -n "$text_field" && "$text_field" != "null" && "$text_field" != "empty" ]]; then
		local text_length=${#text_field}
		if ((text_length > MAX_TEXT_LENGTH)); then
			echo "parse_payload:: text field length ($text_length) exceeds Slack's maximum of $MAX_TEXT_LENGTH characters" >&2
			return 1
		fi
		payload=$(jq --arg text "$text_field" '. + {text: $text}' <<<"$payload")
	fi

	local bot_identity_username
	local bot_identity_icon_emoji
	local bot_identity_icon_url
	bot_identity_username=$(jq -r '.params.username // empty' "$INPUT_PAYLOAD")
	bot_identity_icon_emoji=$(jq -r '.params.icon_emoji // empty' "$INPUT_PAYLOAD")
	bot_identity_icon_url=$(jq -r '.params.icon_url // empty' "$INPUT_PAYLOAD")
	if [[ -n "$bot_identity_username" ]]; then
		payload=$(jq --arg username "$bot_identity_username" '. + {username: $username}' <<<"$payload")
	fi
	if [[ -n "$bot_identity_icon_emoji" ]]; then
		payload=$(jq --arg icon_emoji "$bot_identity_icon_emoji" '. + {icon_emoji: $icon_emoji}' <<<"$payload")
	fi
	if [[ -n "$bot_identity_icon_url" ]]; then
		payload=$(jq --arg icon_url "$bot_identity_icon_url" '. + {icon_url: $icon_url}' <<<"$payload")
	fi

	echo "$payload"

	return 0
}

# Process blocks array and create Slack payload with blocks and attachments
#
# Uses global variables: INPUT_PAYLOAD, CHANNEL, DELIVERY_METHOD from load_configuration
#
# Outputs:
#   Writes complete Slack API payload JSON to stdout
#
# Returns:
#   0 on success
#   1 if block processing fails
process_blocks() {
	unset BLOCKS_FILE ATTACHMENTS_FILE

	local blocks_json
	blocks_json=$(jq -r '.params.blocks // []' "$INPUT_PAYLOAD")
	local blocks_file
	blocks_file=$(mktemp "$_SLACK_WORKSPACE/process_blocks.blocks.XXXXXX")
	echo '[]' >"$blocks_file"

	local attachments_file
	attachments_file=$(mktemp "$_SLACK_WORKSPACE/process_blocks.attachments.XXXXXX")
	echo '[]' >"$attachments_file"

	BLOCKS_FILE="$blocks_file"
	ATTACHMENTS_FILE="$attachments_file"

	export BLOCKS_FILE ATTACHMENTS_FILE

	if [[ "$blocks_json" == "[]" ]]; then
		echo "process_blocks:: no blocks to process, skipping" >&2

		return 0
	fi

	local block_index=0

	# Process each block in the blocks array
	while read -r block_item; do
		# Expand block-level from_file before type/value extraction
		if jq -e '.from_file or (.type == "from_file")' <<<"$block_item" >/dev/null 2>&1; then
			local block_from_file_path
			block_from_file_path=$(jq -r '.path // .from_file // empty' <<<"$block_item")
			if [[ -z "$block_from_file_path" ]]; then
				echo "parse_payload:: block from_file path is empty" >&2
				return 1
			fi
			local loaded_content
			loaded_content=$(_load_block_item_from_file "$block_from_file_path") || return 1
			echo "process_blocks:: expanded block from file: ${block_from_file_path}" >&2
			if echo "$loaded_content" | jq -e 'type == "array"' >/dev/null 2>&1; then
				while read -r block_item; do
					_process_blocks_append_block "$block_item" || return 1
				done < <(echo "$loaded_content" | jq -c '.[]')
				continue
			fi
			block_item="$loaded_content"
		fi

		_process_blocks_append_block "$block_item" || return 1
	done < <(jq -r -c '.[]' <<<"$blocks_json")

	local block_count_debug
	local attachment_count_debug
	block_count_debug=$(jq '. | length' "$BLOCKS_FILE")
	attachment_count_debug=$(jq '. | length' "$ATTACHMENTS_FILE")
	echo "process_blocks:: completed: ${block_count_debug} blocks, ${attachment_count_debug} attachments" >&2

	if ! _validate_block_counts "$BLOCKS_FILE" "$ATTACHMENTS_FILE"; then
		return 1
	fi

	local thread_ts
	thread_ts=$(jq -r '.params.thread_ts // ""' "$INPUT_PAYLOAD")

	if [[ -n "$thread_ts" && "$thread_ts" != "null" && "$thread_ts" != "empty" ]]; then
		local converted_ts
		converted_ts=$(convert_thread_ts "$thread_ts")
		local convert_thread_ts_exit_code=$?
		if [[ "$convert_thread_ts_exit_code" -ne 0 ]]; then
			echo "parse_payload:: failed to convert thread_ts from permalink" >&2
			return 1
		fi
		thread_ts="$converted_ts"
	fi

	local thread_replies_raw
	thread_replies_raw=$(jq '.params.thread.replies // empty' "$INPUT_PAYLOAD")
	if ! _validate_thread_replies "$thread_replies_raw"; then
		return 1
	fi

	local text_field
	text_field=$(jq -r '.params.text // empty' "$INPUT_PAYLOAD")

	local payload
	# shellcheck disable=SC2153
	if ! payload=$(_build_slack_payload "$CHANNEL" "$BLOCKS_FILE" "$ATTACHMENTS_FILE" "$thread_ts" "$text_field" "$thread_replies_raw" "${DELIVERY_METHOD:-api}"); then
		return 1
	fi

	echo "$payload"

	return 0
}

# Resolve named or invalid color strings to hex for legacy attachments
#
# Arguments:
#   $1 - block_color: color string, may be empty, hex, or named token
#
# Outputs:
#   Writes resolved hex color or empty string to stdout
#
# Returns:
#   0 always
_resolve_block_color() {
	local block_color="$1"

	if [[ -z "$block_color" ]]; then
		echo ""
		return 0
	fi

	if [[ "$block_color" =~ ^#[0-9A-Fa-f]{6}$ ]]; then
		echo "$block_color"
		return 0
	fi

	case "$block_color" in
	"danger") echo "$DANGER_COLOR" ;;
	"success") echo "$SUCCESS_COLOR" ;;
	"warning") echo "$WARN_COLOR" ;;
	*) echo "$DANGER_COLOR" ;;
	esac

	return 0
}

# Parse block_item JSON into type, value, and optional color
#
# Arguments:
#   $1 - block_item: JSON object in type-field or single-key format
#
# Side Effects:
#   Sets globals _EXTRACT_BLOCK_TYPE, _EXTRACT_BLOCK_VALUE, _EXTRACT_BLOCK_COLOR
#   Caller should copy these to locals immediately
#
# Returns:
#   0 on success
#   1 if block_item is empty
_extract_block_type_and_value() {
	local block_item="$1"

	if [[ -z "$block_item" ]]; then
		echo "_extract_block_type_and_value:: block_item is required" >&2
		return 1
	fi

	if jq -e '.type' <<<"$block_item" >/dev/null 2>&1; then
		_EXTRACT_BLOCK_TYPE=$(jq -r '.type' <<<"$block_item")
		_EXTRACT_BLOCK_VALUE=$(jq 'del(.type, .color)' <<<"$block_item")
		_EXTRACT_BLOCK_COLOR=$(jq -r '.color // empty' <<<"$block_item")

		if [[ "$_EXTRACT_BLOCK_TYPE" == "section" ]]; then
			if ! jq -e '.type' <<<"$_EXTRACT_BLOCK_VALUE" >/dev/null 2>&1; then
				if jq -e '.text' <<<"$_EXTRACT_BLOCK_VALUE" >/dev/null 2>&1; then
					_EXTRACT_BLOCK_VALUE=$(jq '. + {type: "text"}' <<<"$_EXTRACT_BLOCK_VALUE")
				elif jq -e '.fields' <<<"$_EXTRACT_BLOCK_VALUE" >/dev/null 2>&1; then
					_EXTRACT_BLOCK_VALUE=$(jq '. + {type: "fields"}' <<<"$_EXTRACT_BLOCK_VALUE")
				fi
			fi
		fi
	else
		local block_entry
		block_entry=$(jq -c 'to_entries[0]' <<<"$block_item")
		_EXTRACT_BLOCK_TYPE=$(jq -r '.key' <<<"$block_entry")
		_EXTRACT_BLOCK_VALUE=$(jq '.value | del(.color)' <<<"$block_entry")
		_EXTRACT_BLOCK_COLOR=$(jq -r '.value.color // empty' <<<"$block_entry")
	fi

	return 0
}

# Helper used by process_blocks to process a single block_item and append to blocks/attachments
#
# Inputs:
#   block_item - JSON object for one block in type-field or key-based format
#
# Side Effects:
#   Updates blocks, attachments, block_index in caller scope
#   Writes to stderr on failure
#
# Returns:
#   0 on success
#   1 if create_block fails
_process_blocks_append_block() {
	local block_item="$1"

	if [[ -z "$block_item" ]]; then
		echo "_process_blocks_append_block:: block_item is required" >&2
		return 1
	fi

	if ! jq . >/dev/null 2>&1 <<<"$block_item"; then
		echo "_process_blocks_append_block:: block_item must be valid JSON" >&2
		return 1
	fi

	if ! _extract_block_type_and_value "$block_item"; then
		return 1
	fi

	local block_type
	local block_value
	local block_color
	local dest
	block_type="$_EXTRACT_BLOCK_TYPE"
	block_value="$_EXTRACT_BLOCK_VALUE"
	block_color="$_EXTRACT_BLOCK_COLOR"

	# Allocate a per-block output file and set CREATE_BLOCK_OUTPUT_FILE for create_block
	local create_block_out
	create_block_out=$(mktemp "$_SLACK_WORKSPACE/process_blocks.block_out.XXXXXX")
	CREATE_BLOCK_OUTPUT_FILE="$create_block_out"
	export CREATE_BLOCK_OUTPUT_FILE

	# Allocate a temp file for in-place jq updates to BLOCKS_FILE / ATTACHMENTS_FILE
	local merge_tmp
	merge_tmp=$(mktemp "$_SLACK_WORKSPACE/process_blocks.merge_tmp.XXXXXX")

	if ! _validate_block_input_size "$block_value" "$block_type"; then
		echo "_process_blocks_append_block:: block input too large for type '$block_type'" >&2
		return 1
	fi

	if [[ "$block_type" == "file" ]] && [[ "${DELIVERY_METHOD:-api}" == "webhook" ]]; then
		echo "_process_blocks_append_block:: file uploads are not supported for webhook delivery" >&2
		return 1
	fi

	if ! create_block "$block_value" "$block_type"; then
		echo "_process_blocks_append_block:: failed to create block type '$block_type': $block_item" >&2
		return 1
	fi

	# A block script may return a JSON array when it needs to emit multiple blocks
	# (e.g. table overflow produces a context block + file block array).
	# Recurse into each element so they each go through the normal append path.
	if jq -e 'type == "array"' "$CREATE_BLOCK_OUTPUT_FILE" >/dev/null 2>&1; then
		local array_item
		while IFS= read -r array_item; do
			_process_blocks_append_block "$array_item" || return 1
		done < <(jq -c '.[]' "$CREATE_BLOCK_OUTPUT_FILE")

		return 0
	fi

	if [[ -n "$block_color" ]] || [[ "$block_type" == "table" ]]; then
		dest="attachments"
	else
		dest="blocks"
	fi
	echo "_process_blocks_append_block:: block ${block_index}: type=${block_type} dest=${dest}" >&2

	if [[ -n "$block_color" ]] || [[ "$block_type" == "table" ]]; then
		if [[ -n "$block_color" ]] && [[ ! "$block_color" =~ ^#[0-9A-Fa-f]{6}$ ]]; then
			block_color=$(_resolve_block_color "$block_color")
		fi
		jq --slurpfile block "$CREATE_BLOCK_OUTPUT_FILE" \
			--arg color "${block_color:-}" \
			'. += [{ color: $color, blocks: [$block[0]]}]' \
			"$ATTACHMENTS_FILE" >"$merge_tmp" && mv "$merge_tmp" "$ATTACHMENTS_FILE"
	else
		jq --slurpfile block "$CREATE_BLOCK_OUTPUT_FILE" \
			'. += [$block[0]]' \
			"$BLOCKS_FILE" >"$merge_tmp" && mv "$merge_tmp" "$BLOCKS_FILE"
	fi

	block_index=$((block_index + 1))

	return 0
}
