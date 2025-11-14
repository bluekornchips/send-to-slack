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
		return 1
	fi

	local text_content
	if ! text_content=$(jq -r '.text // empty' <<<"$input"); then
		echo "create_markdown:: invalid JSON format" >&2
		return 1
	fi
	if [[ -z "$text_content" ]]; then
		echo "create_markdown:: text field is required" >&2
		return 1
	fi

	if [[ "${#text_content}" -gt "$MAX_TEXT_LENGTH" ]]; then
		echo "create_markdown:: text must be $MAX_TEXT_LENGTH characters or less" >&2
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
