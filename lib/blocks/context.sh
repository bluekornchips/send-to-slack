#!/usr/bin/env bash
#
# Context Block implementation following Slack Block Kit guidelines
# Ref: https://docs.slack.dev/reference/block-kit/blocks/context-block
#
set -eo pipefail

########################################################
# Constants
########################################################
BLOCK_TYPE="context"
MAX_ELEMENT_TEXT_LENGTH=2000

########################################################
# Documentation URLs
########################################################
DOC_URL_CONTEXT_BLOCK="https://docs.slack.dev/reference/block-kit/blocks/context-block"

########################################################
# Example Strings
########################################################
EXAMPLE_CONTEXT_BLOCK='{"elements": [{"type": "plain_text", "text": "Context info"}]}'

# Process context block and create Slack Block Kit context block format
#
# Inputs:
# - Reads JSON from stdin with context configuration
#
# Side Effects:
# - Outputs Slack Block Kit context block JSON to stdout
#
# Returns:
# - 0 on successful block creation with valid elements
# - 1 if input is empty, invalid JSON, or missing required elements field
create_context() {
	local input
	input=$(cat)

	if [[ -z "$input" ]]; then
		echo "create_context:: input is required" >&2
		return 1
	fi

	if ! jq . >/dev/null 2>&1 <<<"$input"; then
		echo "create_context:: input must be valid JSON" >&2
		return 1
	fi

	# Validate required elements field
	if ! jq -e '.elements' <<<"$input" >/dev/null 2>&1; then
		echo "create_context:: elements field is required" >&2
		echo "create_context:: Example: $EXAMPLE_CONTEXT_BLOCK" >&2
		return 1
	fi

	# Validate elements is an array
	if ! jq -e '.elements | type == "array"' <<<"$input" >/dev/null 2>&1; then
		echo "create_context:: elements must be an array" >&2
		echo "create_context:: Example: $EXAMPLE_CONTEXT_BLOCK" >&2
		return 1
	fi

	# Validate elements array is not empty
	local elements_length
	if ! elements_length=$(jq -r '.elements | length' <<<"$input"); then
		echo "create_context:: invalid JSON format" >&2
		return 1
	fi
	if [[ "$elements_length" -eq 0 ]]; then
		echo "create_context:: elements array must not be empty" >&2
		echo "create_context:: Example: $EXAMPLE_CONTEXT_BLOCK" >&2
		return 1
	fi

	# Validate each element's text length (only for text-based elements)
	local element_index=0
	while read -r element_entry; do
		local element_type
		element_type=$(jq -r '.type // ""' <<<"$element_entry" 2>/dev/null)
		if [[ -n "$element_type" ]] && [[ "$element_type" != "null" ]] && [[ "$element_type" != "image" ]]; then
			local element_text
			element_text=""
			if jq -e '.text' <<<"$element_entry" >/dev/null 2>&1; then
				element_text=$(jq -r '.text // ""' <<<"$element_entry" 2>/dev/null)
			fi
			if [[ -n "$element_text" ]] && [[ "$element_text" != "null" ]]; then
				local element_text_length
				element_text_length=${#element_text}
				if ((element_text_length > MAX_ELEMENT_TEXT_LENGTH)); then
					echo "create_context:: element at index $element_index text length ($element_text_length) exceeds maximum of $MAX_ELEMENT_TEXT_LENGTH characters" >&2
					echo "create_context:: See context block limits: $DOC_URL_CONTEXT_BLOCK" >&2
					return 1
				fi
			fi
		fi
		element_index=$((element_index + 1))
	done < <(jq -r -c '.elements[]' <<<"$input")

	# Create the context block
	local block
	block=$(jq -n \
		--arg block_type "$BLOCK_TYPE" \
		--argjson input "$input" \
		'{ type: $block_type, elements: $input.elements }')

	# Add optional block_id if present
	if jq -e '.block_id' <<<"$input" >/dev/null 2>&1; then
		local block_id
		if ! block_id=$(jq -r '.block_id' <<<"$input"); then
			echo "create_context:: invalid JSON format" >&2
			return 1
		fi
		if [[ -n "$block_id" && "$block_id" != "null" ]]; then
			block=$(jq --arg block_id "$block_id" '. + {block_id: $block_id}' <<<"$block")
		fi
	fi

	echo "$block"
	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	create_context "$@"
fi
