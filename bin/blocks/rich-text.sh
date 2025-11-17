#!/usr/bin/env bash
#
# Rich Text Block implementation for wysiwyg content
# Ref: https://docs.slack.dev/reference/block-kit/blocks/rich-text-block
#
set -eo pipefail

BLOCK_TYPE="rich_text"
MAX_RICH_TEXT_CHARS=4000

UPLOAD_FILE_SCRIPT="bin/file-upload.sh"

# Upload the content as a file if it exceeds the max allowed characters
handle_oversize_text() {
	local extracted_text="$1"

	local file_path
	file_path=$(mktemp /tmp/send-to-slack-oversize-rich-text-XXXXXX.txt)
	trap 'rm -f "$file_path"' RETURN EXIT

	# Write the extracted text to the file
	echo "$extracted_text" >"$file_path"

	local text="Notification content exceeded the max allowed characters of $MAX_RICH_TEXT_CHARS. Content has been uploaded and is available as a file."

	local upload_script_path
	if [[ "$UPLOAD_FILE_SCRIPT" = /* ]]; then
		# Absolute path, use as-is
		upload_script_path="$UPLOAD_FILE_SCRIPT"
	else
		# Relative path, prepend SEND_TO_SLACK_ROOT
		upload_script_path="${SEND_TO_SLACK_ROOT}/${UPLOAD_FILE_SCRIPT}"
	fi

	if [[ ! -f "$upload_script_path" ]]; then
		echo "handle_oversize_text:: file upload script not found: $upload_script_path" >&2
		return 1
	fi

	if [[ ! -r "$upload_script_path" ]]; then
		echo "handle_oversize_text:: file upload script not readable: $upload_script_path" >&2
		return 1
	fi

	local new_block_input_json
	new_block_input_json="$(
		jq -n \
			--arg path "$file_path" \
			--arg text "$text" \
			'{ file: { path: $path, text: $text } }'
	)"

	# Upload the file
	block=$("$upload_script_path" <<<"$new_block_input_json")

	echo "$block"

	return 0
}

# Process json input and create Slack Block Kit rich text block format
#
# Inputs:
# - Reads JSON from stdin with rich text configuration
#
# Side Effects:
# - Outputs Slack Block Kit rich text block JSON to stdout
create_rich_text() {
	local input
	input=$(cat)

	if [[ -z "${input}" ]]; then
		echo "create_rich_text:: input is required" >&2
		return 1
	fi

	local input_json
	input_json=$(mktemp /tmp/send-to-slack-XXXXXX)
	trap 'rm -f "$input_json"' RETURN EXIT
	echo "$input" >"$input_json"

	if ! jq . "$input_json" >/dev/null 2>&1; then
		echo "create_rich_text:: input must be valid JSON" >&2
		return 1
	fi

	# Validate required fields
	if ! jq -e '.elements' "$input_json" >/dev/null 2>&1; then
		echo "create_rich_text:: elements field is required" >&2
		return 1
	fi

	local input_elements
	input_elements=$(jq '.elements' "$input_json")

	local block
	local block_id

	block_id=$(jq '.block_id // empty' "$input_json")

	# Extract all text content and calculate length
	local extracted_text
	extracted_text=$(jq -r '
		def extract_text:
			if .type == "text" then
				.text // ""
			elif .elements then
				(.elements | map(extract_text) | join(""))
			else
				""
			end;
		.elements // [] | map(extract_text) | join("")
	' "$input_json")

	local text_length=${#extracted_text}

	# If the text length exceeds the max allowed characters, instead we need
	# to upload the content as a file.
	if [[ "$text_length" -gt "$MAX_RICH_TEXT_CHARS" ]]; then
		handle_oversize_text "$extracted_text"
		return $?
	fi

	block=$(jq -n \
		--arg block_type "$BLOCK_TYPE" \
		--arg block_id "$block_id" \
		--argjson input_elements "$input_elements" \
		'{
			type: $block_type,
			block_id: $block_id,
			elements: $input_elements,
		}')

	echo "$block"

	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	create_rich_text "$@"
fi
