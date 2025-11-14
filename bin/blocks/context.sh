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
		return 1
	fi

	# Validate elements is an array
	if ! jq -e '.elements | type == "array"' <<<"$input" >/dev/null 2>&1; then
		echo "create_context:: elements must be an array" >&2
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
		return 1
	fi

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
