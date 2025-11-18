#!/usr/bin/env bash
#
# Actions Block implementation following Slack Block Kit guidelines
# Ref: https://docs.slack.dev/reference/block-kit/blocks/actions-block/
#
set -eo pipefail

########################################################
# Constants
########################################################
MAX_ELEMENTS=25
SUPPORTED_ELEMENT_TYPES=("button")

# Create button element following Slack Block Kit format
#
# Inputs:
# - $1 button_json, JSON string with button configuration
#
# Side Effects:
# - Outputs button element JSON to stdout
#
# Returns:
# - 0 on successful button creation
# - 1 if button_json is empty, invalid, or missing required fields
#
# Ref: https://docs.slack.dev/reference/block-kit/blocks/actions-block/#button
create_button_element() {
	local button_json="$1"

	if [[ -z "$button_json" ]]; then
		echo "create_button_element:: button_json is required" >&2
		return 1
	fi

	if ! jq . >/dev/null 2>&1 <<<"$button_json"; then
		echo "create_button_element:: button_json must be valid JSON" >&2
		return 1
	fi

	if ! jq -e '.text' <<<"$button_json" >/dev/null 2>&1; then
		echo "create_button_element:: text is required" >&2
		return 1
	fi

	local text_type
	if ! text_type=$(jq -r '.text.type // empty' <<<"$button_json"); then
		echo "create_button_element:: invalid JSON format" >&2
		return 1
	fi
	if [[ -z "$text_type" ]] || [[ "$text_type" == "null" ]]; then
		echo "create_button_element:: text.type is required" >&2
		return 1
	fi

	local action_id
	if ! action_id=$(jq -r '.action_id // empty' <<<"$button_json"); then
		echo "create_button_element:: invalid JSON format" >&2
		return 1
	fi
	if [[ -z "$action_id" ]] || [[ "$action_id" == "null" ]]; then
		echo "create_button_element:: action_id is required" >&2
		return 1
	fi

	local button
	button=$(jq -n \
		--argjson text "$(jq '.text' <<<"$button_json")" \
		--arg action_id "$action_id" \
		'{
			type: "button",
			text: $text,
			action_id: $action_id
		}')

	local url
	if url=$(jq -r '.url // empty' <<<"$button_json" 2>/dev/null); then
		if [[ -n "$url" ]] && [[ "$url" != "null" ]]; then
			button=$(echo "$button" | jq --arg url "$url" '. + {url: $url}')
		fi
	fi

	local value
	if value=$(jq -r '.value // empty' <<<"$button_json" 2>/dev/null); then
		if [[ -n "$value" ]] && [[ "$value" != "null" ]]; then
			button=$(echo "$button" | jq --arg value "$value" '. + {value: $value}')
		fi
	fi

	local style
	if style=$(jq -r '.style // empty' <<<"$button_json" 2>/dev/null); then
		if [[ -n "$style" ]] && [[ "$style" != "null" ]]; then
			button=$(echo "$button" | jq --arg style "$style" '. + {style: $style}')
		fi
	fi

	echo "$button"
	return 0
}

# Process actions block and create Slack actions block format
#
# Inputs:
# - Reads JSON from stdin with actions configuration
#
# Side Effects:
# - Outputs Slack Block Kit actions block JSON to stdout
#
# Returns:
# - 0 on successful actions block creation
# - 1 if input is invalid, JSON parsing fails, or block creation fails
create_actions() {
	local input

	input=$(cat)

	if [[ -z "$input" ]]; then
		echo "create_actions:: input is required" >&2
		return 1
	fi

	if ! jq . >/dev/null 2>&1 <<<"$input"; then
		echo "create_actions:: input must be valid JSON" >&2
		return 1
	fi

	local elements_json
	if ! elements_json=$(jq '.elements // empty' <<<"$input"); then
		echo "create_actions:: invalid JSON format" >&2
		return 1
	fi
	if [[ -z "$elements_json" ]] || [[ "$elements_json" == "null" ]] || [[ "$elements_json" == "[]" ]]; then
		echo "create_actions:: elements array is required" >&2
		return 1
	fi

	local elements_count
	elements_count=$(jq 'length' <<<"$elements_json")
	if ((elements_count > MAX_ELEMENTS)); then
		echo "create_actions:: elements array cannot exceed $MAX_ELEMENTS elements" >&2
		return 1
	fi

	local elements="[]"
	local element_type
	local element_value

	while read -r element_entry; do
		if ! element_type=$(jq -r '.type // empty' <<<"$element_entry"); then
			echo "create_actions:: invalid element JSON format" >&2
			return 1
		fi

		if ! [[ " ${SUPPORTED_ELEMENT_TYPES[*]} " =~ ${element_type} ]]; then
			echo "create_actions:: unsupported element type: $element_type. Only button is supported." >&2
			return 1
		fi

		local element
		if [[ "$element_type" == "button" ]]; then
			if ! element=$(create_button_element "$element_entry"); then
				return 1
			fi
		fi

		elements=$(jq --argjson element "$element" '. += [$element]' <<<"$elements")

	done < <(jq -r -c '.[]' <<<"$elements_json")

	local block_id
	block_id=$(jq -r '.block_id // empty' <<<"$input")

	local block
	block=$(jq -n \
		--argjson elements "$elements" \
		--arg block_id "$block_id" \
		'{
			type: "actions",
			elements: $elements
		}')

	if [[ -n "$block_id" ]] && [[ "$block_id" != "null" ]]; then
		block=$(echo "$block" | jq --arg block_id "$block_id" '. + {block_id: $block_id}')
	fi

	echo "$block"
	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	create_actions "$@"
fi
