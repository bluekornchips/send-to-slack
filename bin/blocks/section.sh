#!/usr/bin/env bash
#
# Section Block implementation following Slack Block Kit guidelines
# Ref: https://docs.slack.dev/reference/block-kit/blocks/section-block/
#
set -eo pipefail

########################################################
# Constants
########################################################
SUPPORTED_TEXT_TYPES=("plain_text" "mrkdwn")
SUPPORTED_SECTION_TYPES=("text" "fields")
MAX_TEXT_LENGTH=3000
MAX_FIELD_TEXT_LENGTH=2000
MAX_FIELDS=10
DEFAULT_TEXT_TYPE="plain_text"

# Create text section block following Slack Block Kit format
#
# Inputs:
# - $1 text_json, JSON string with text configuration
#
# Side Effects:
# - Outputs text object JSON to stdout
#
# Returns:
# - 0 on successful text section creation with valid type and content
# - 1 if text_json is empty, type is unsupported, or text exceeds length limit
#
# Text can be "plain_text" or "mrkdwn"
# Ref: https://docs.slack.dev/reference/block-kit/composition-objects/text-object/
create_text_section() {
	local text_json="$1"

	if [[ -z "$text_json" ]]; then
		echo "create_text_section:: text_json is required" >&2
		return 1
	fi

	local text_type
	# Type can be empty, defaults to "plain_text"
	if ! text_type=$(jq -r \
		--arg default "$DEFAULT_TEXT_TYPE" '.type // $default' <<<"$text_json"); then
		echo "create_text_section:: invalid JSON format" >&2
		return 1
	fi
	local pattern
	pattern=" ${SUPPORTED_TEXT_TYPES[*]} "
	if ! [[ "$pattern" =~ ${text_type} ]]; then
		echo "create_text_section:: text type must be one of: ${SUPPORTED_TEXT_TYPES[*]}" >&2
		return 1
	fi

	local text
	if ! text=$(jq -r '.text' <<<"$text_json"); then
		echo "create_text_section:: invalid JSON format" >&2
		return 1
	fi
	if [[ "${#text}" -gt "$MAX_TEXT_LENGTH" ]]; then
		echo "create_text_section:: text length must be less than $MAX_TEXT_LENGTH" >&2
		return 1
	fi

	echo "$text_json"
	return 0
}

# Create fields section block following Slack Block Kit format
#
# Inputs:
# - $1 fields_json, JSON string with fields array configuration
#
# Side Effects:
# - Outputs fields array JSON to stdout
#
# Returns:
# - 0 on successful fields section creation with valid array of text objects
# - 1 if fields_json is empty, invalid, exceeds limits, or contains invalid text objects
#
# Fields is an array of text objects (up to 10 items, each up to 2000 characters)
# See: https://docs.slack.dev/reference/block-kit/blocks/section#fields
create_fields_section() {
	local fields_json="$1"

	if [[ -z "$fields_json" ]]; then
		echo "create_fields_section:: fields_json is required" >&2
		return 1
	fi

	# Validate fields_json is valid JSON
	if ! jq . >/dev/null 2>&1 <<<"$fields_json"; then
		echo "create_fields_section:: fields_json must be valid JSON" >&2
		return 1
	fi

	# Validate fields is an array
	if ! jq -e 'type == "array"' <<<"$fields_json" >/dev/null 2>&1; then
		echo "create_fields_section:: fields must be an array" >&2
		return 1
	fi

	# Validate fields array is not empty
	local fields_length
	if ! fields_length=$(jq -r 'length' <<<"$fields_json"); then
		echo "create_fields_section:: invalid JSON format" >&2
		return 1
	fi
	if [[ "$fields_length" -eq 0 ]]; then
		echo "create_fields_section:: fields array must not be empty" >&2
		return 1
	fi

	# Validate fields array does not exceed maximum
	if [[ "$fields_length" -gt "$MAX_FIELDS" ]]; then
		echo "create_fields_section:: fields array cannot exceed $MAX_FIELDS items" >&2
		return 1
	fi

	# Validate each field is a valid text object
	local validated_fields="[]"
	local field_index=0

	while read -r field_entry; do
		# Validate field is valid JSON
		if ! jq . >/dev/null 2>&1 <<<"$field_entry"; then
			echo "create_fields_section:: field at index $field_index must be valid JSON" >&2
			return 1
		fi

		# Validate field using create_text_section logic
		local validated_field
		if ! validated_field=$(create_text_section "$field_entry"); then
			echo "create_fields_section:: field at index $field_index is invalid" >&2
			return 1
		fi

		# Validate field text length (fields have shorter limit than regular text)
		local field_text
		if ! field_text=$(jq -r '.text' <<<"$validated_field"); then
			echo "create_fields_section:: invalid JSON format for field at index $field_index" >&2
			return 1
		fi
		if [[ "${#field_text}" -gt "$MAX_FIELD_TEXT_LENGTH" ]]; then
			echo "create_fields_section:: field at index $field_index text length must be less than $MAX_FIELD_TEXT_LENGTH" >&2
			return 1
		fi

		# Add validated field to array
		validated_fields=$(jq --argjson field "$validated_field" '. += [$field]' <<<"$validated_fields")

		((field_index++))
	done < <(jq -r -c '.[]' <<<"$fields_json")

	echo "$validated_fields"

	return 0
}

# Process section block and create Slack section block format
#
# Inputs:
# - Reads JSON from stdin with section configuration
#
# Side Effects:
# - Outputs Slack Block Kit section block JSON to stdout
#
# Returns:
# - 0 on successful section block creation
# - 1 if input is invalid, JSON parsing fails, or block creation fails
create_section() {
	local input

	input=$(cat)

	if [[ -z "$input" ]]; then
		echo "create_section:: input is required" >&2
		return 1
	fi

	if ! jq . >/dev/null 2>&1 <<<"$input"; then
		echo "create_section:: input must be valid JSON" >&2
		return 1
	fi

	local section_type
	if ! section_type=$(jq -r '.type' <<<"$input"); then
		echo "create_section:: invalid JSON format" >&2
		return 1
	fi
	local pattern
	pattern=" ${SUPPORTED_SECTION_TYPES[*]} "
	if ! [[ "$pattern" =~ ${section_type} ]]; then
		echo "create_section:: section type must be one of: ${SUPPORTED_SECTION_TYPES[*]}" >&2
		return 1
	fi

	local text
	local fields
	if ! text=$(jq -r '.text // empty' <<<"$input"); then
		echo "create_section:: invalid JSON format" >&2
		return 1
	fi
	if ! fields=$(jq -r '.fields // empty' <<<"$input"); then
		echo "create_section:: invalid JSON format" >&2
		return 1
	fi

	local block
	local has_text=false
	local has_fields=false

	if [[ -n "$text" ]] && [[ "$text" != "null" ]]; then
		if ! block=$(create_text_section "$text"); then
			return 1
		fi
		has_text=true
	fi

	if [[ -n "$fields" ]] && [[ "$fields" != "null" ]] && [[ "$fields" != "[]" ]]; then
		if ! block=$(create_fields_section "$fields"); then
			return 1
		fi
		has_fields=true
	fi

	if [[ "$has_text" == true ]] && [[ "$has_fields" == true ]]; then
		echo "create_section:: section cannot have both text and fields" >&2
		return 1
	fi

	if [[ "$has_text" == false ]] && [[ "$has_fields" == false ]]; then
		echo "create_section:: section must have either text or fields" >&2
		return 1
	fi

	local section_block
	if [[ "$has_text" == true ]]; then
		section_block=$(jq -n --argjson block "$block" '{ type: "section", text: $block }')
	else
		section_block=$(jq -n --argjson block "$block" '{ type: "section", fields: $block }')
	fi

	# Add optional block_id if present
	if jq -e '.block_id' <<<"$input" >/dev/null 2>&1; then
		local block_id
		if ! block_id=$(jq -r '.block_id' <<<"$input"); then
			echo "create_section:: invalid JSON format" >&2
			return 1
		fi
		if [[ -n "$block_id" && "$block_id" != "null" ]]; then
			section_block=$(jq --arg block_id "$block_id" '. + {block_id: $block_id}' <<<"$section_block")
		fi
	fi

	echo "$section_block"

	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	create_section "$@"
fi
