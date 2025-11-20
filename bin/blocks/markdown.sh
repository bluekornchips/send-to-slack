#!/usr/bin/env bash
#
# Markdown Block implementation following Slack Block Kit guidelines
# Ref: https://docs.slack.dev/reference/block-kit/blocks/markdown-block/
#
set -eo pipefail

########################################################
# Constants
########################################################
BLOCK_TYPE="markdown"
MAX_TEXT_LENGTH=12000

########################################################
# Documentation URLs
########################################################
DOC_URL_MARKDOWN_BLOCK="https://docs.slack.dev/reference/block-kit/blocks/markdown-block"

########################################################
# Example Strings
########################################################
EXAMPLE_MARKDOWN_BLOCK='{"text": "*Bold* and _italic_ text"}'

# Process markdown block and create Slack Block Kit markdown block format
#
# Inputs:
# - Reads JSON from stdin with markdown configuration
#
# Side Effects:
# - Outputs Slack Block Kit markdown block JSON to stdout
#
# Returns:
# - 0 on successful block creation with valid text
# - 1 if input is empty, invalid JSON, or missing required text field
create_markdown() {
	local input
	input=$(cat)

	if [[ -z "$input" ]]; then
		echo "create_markdown:: input is required" >&2
		return 1
	fi

	if ! jq . >/dev/null 2>&1 <<<"$input"; then
		echo "create_markdown:: input must be valid JSON" >&2
		return 1
	fi

	if ! jq -e '.text' <<<"$input" >/dev/null 2>&1; then
		echo "create_markdown:: text field is required" >&2
		echo "create_markdown:: Example: $EXAMPLE_MARKDOWN_BLOCK" >&2
		return 1
	fi

	local text_content
	if ! text_content=$(jq -r '.text // empty' <<<"$input"); then
		echo "create_markdown:: invalid JSON format" >&2
		return 1
	fi
	if [[ -z "$text_content" ]] || [[ "$text_content" == "null" ]]; then
		echo "create_markdown:: text field is required and cannot be empty" >&2
		echo "create_markdown:: Example: $EXAMPLE_MARKDOWN_BLOCK" >&2
		return 1
	fi

	local text_length
	text_length=${#text_content}
	if ((text_length > MAX_TEXT_LENGTH)); then
		echo "create_markdown:: text length ($text_length) exceeds maximum of $MAX_TEXT_LENGTH characters" >&2
		echo "create_markdown:: See markdown block limits: $DOC_URL_MARKDOWN_BLOCK" >&2
		return 1
	fi

	local block
	block=$(jq -n \
		--arg block_type "$BLOCK_TYPE" \
		--arg text "$text_content" \
		'{ type: $block_type, text: $text }')

	echo "$block"

	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	create_markdown "$@"
fi
