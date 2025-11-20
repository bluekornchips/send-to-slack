#!/usr/bin/env bash
#
# Header Block implementation following Slack Block Kit guidelines
# Ref: https://docs.slack.dev/reference/block-kit/blocks/header-block
#
set -eo pipefail

########################################################
# Constants
########################################################
BLOCK_TYPE="header"
REQUIRED_TEXT_TYPE="plain_text"
MAX_HEADER_LENGTH=150

########################################################
# Documentation URLs
########################################################
DOC_URL_HEADER_BLOCK="https://docs.slack.dev/reference/block-kit/blocks/header-block"

########################################################
# Example Strings
########################################################
EXAMPLE_HEADER_BLOCK='{"text": {"type": "plain_text", "text": "Header Title"}}'

# Process header block and create Slack Block Kit header block format
#
# Inputs:
# - Reads JSON from stdin with header configuration
#
# Side Effects:
# - Outputs Slack Block Kit header block JSON to stdout
#
# Returns:
# - 0 on successful block creation with valid text
# - 1 if input is empty, invalid JSON, or missing required text field
create_header() {
	local input
	input=$(cat)

	if [[ -z "$input" ]]; then
		echo "create_header:: input is required" >&2
		return 1
	fi

	if ! jq . >/dev/null 2>&1 <<<"$input"; then
		echo "create_header:: input must be valid JSON" >&2
		return 1
	fi

	if ! jq -e '.text' <<<"$input" >/dev/null 2>&1; then
		echo "create_header:: text field is required" >&2
		echo "create_header:: Example: $EXAMPLE_HEADER_BLOCK" >&2
		return 1
	fi

	local text_type
	if ! text_type=$(jq -r '.text.type // empty' <<<"$input"); then
		echo "create_header:: invalid JSON format" >&2
		return 1
	fi
	if [[ "$text_type" != "$REQUIRED_TEXT_TYPE" ]]; then
		echo "create_header:: text type must be $REQUIRED_TEXT_TYPE" >&2
		echo "create_header:: See header block docs: $DOC_URL_HEADER_BLOCK" >&2
		return 1
	fi

	local text_content
	if ! text_content=$(jq -r '.text.text // empty' <<<"$input"); then
		echo "create_header:: invalid JSON format" >&2
		return 1
	fi
	if [[ -z "$text_content" ]] || [[ "$text_content" == "null" ]]; then
		echo "create_header:: text.text field is required and cannot be empty" >&2
		echo "create_header:: Example: $EXAMPLE_HEADER_BLOCK" >&2
		return 1
	fi

	local text_length
	text_length=${#text_content}
	if ((text_length > MAX_HEADER_LENGTH)); then
		echo "create_header:: header text must be $MAX_HEADER_LENGTH characters or less" >&2
		echo "create_header:: See header block limits: $DOC_URL_HEADER_BLOCK" >&2
		return 1
	fi

	local block
	block=$(jq -n \
		--arg block_type "$BLOCK_TYPE" \
		--argjson input "$input" \
		'{ type: $block_type, text: $input.text }')

	# Add optional block_id if present
	if jq -e '.block_id' <<<"$input" >/dev/null 2>&1; then
		local block_id
		if ! block_id=$(jq -r '.block_id' <<<"$input"); then
			echo "create_header:: invalid JSON format" >&2
			return 1
		fi
		block=$(jq --arg block_id "$block_id" '. + {block_id: $block_id}' <<<"$block")
	fi

	echo "$block"

	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	create_header "$@"
fi
