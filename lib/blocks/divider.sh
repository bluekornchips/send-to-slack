#!/usr/bin/env bash
#
# Divider Block implementation following Slack Block Kit guidelines
# Ref: https://docs.slack.dev/reference/block-kit/blocks/divider-block
#
set -eo pipefail

########################################################
# Constants
########################################################
BLOCK_TYPE="divider"

# Process divider block and create Slack Block Kit divider block format
#
# Inputs:
# - Reads JSON from stdin with divider configuration, optional block_id
#
# Side Effects:
# - Outputs Slack Block Kit divider block JSON to stdout
#
# Returns:
# - 0 on successful block creation
# - 1 if input is invalid JSON
create_divider() {
	local input
	input=$(cat)

	# Divider block has no required fields, but validate JSON if provided
	if [[ -n "$input" ]]; then
		if ! jq . >/dev/null 2>&1 <<<"$input"; then
			echo "create_divider:: input must be valid JSON" >&2
			return 1
		fi
	fi

	# Create the divider block
	local block
	block=$(jq -n --arg block_type "$BLOCK_TYPE" '{ type: $block_type }')

	# Add optional block_id if present in input
	if [[ -n "$input" ]] && jq -e '.block_id' <<<"$input" >/dev/null 2>&1; then
		local block_id
		if ! block_id=$(jq -r '.block_id' <<<"$input"); then
			echo "create_divider:: invalid JSON format" >&2
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
	create_divider "$@"
fi
