#!/usr/bin/env bash
#
# Image Block implementation following Slack Block Kit guidelines
# Ref: https://docs.slack.dev/reference/block-kit/blocks/image-block/
#
set -eo pipefail

########################################################
# Constants
########################################################
BLOCK_TYPE="image"
MAX_ALT_TEXT_LENGTH=2000
MAX_TITLE_TEXT_LENGTH=2000
MAX_BLOCK_ID_LENGTH=255

# Process image block and create Slack Block Kit image block format
#
# Inputs:
# - Reads JSON from stdin with image configuration
#
# Side Effects:
# - Outputs Slack Block Kit image block JSON to stdout
#
# Returns:
# - 0 on successful block creation with valid fields
# - 1 if input is empty, invalid JSON, or missing required fields
create_image() {
	local input
	input=$(cat)

	if [[ -z "$input" ]]; then
		echo "create_image:: input is required" >&2
		return 1
	fi

	if ! jq . >/dev/null 2>&1 <<<"$input"; then
		echo "create_image:: input must be valid JSON" >&2
		return 1
	fi

	local has_image_url=false
	local has_slack_file=false

	if jq -e 'has("image_url")' <<<"$input" >/dev/null 2>&1; then
		local image_url_check
		image_url_check=$(jq -r '.image_url // empty' <<<"$input")
		if [[ -n "$image_url_check" ]] && [[ "$image_url_check" != "null" ]]; then
			has_image_url=true
		fi
	fi

	if jq -e 'has("slack_file")' <<<"$input" >/dev/null 2>&1; then
		local slack_file_check
		slack_file_check=$(jq -r '.slack_file // empty' <<<"$input")
		if [[ -n "$slack_file_check" ]] && [[ "$slack_file_check" != "null" ]]; then
			has_slack_file=true
		fi
	fi

	if [[ "$has_image_url" == false ]] && [[ "$has_slack_file" == false ]]; then
		echo "create_image:: either image_url or slack_file field is required" >&2
		return 1
	fi

	if [[ "$has_image_url" == true ]] && [[ "$has_slack_file" == true ]]; then
		echo "create_image:: cannot have both image_url and slack_file" >&2
		return 1
	fi

	local image_url=""
	if [[ "$has_image_url" == true ]]; then
		if ! image_url=$(jq -r '.image_url' <<<"$input"); then
			echo "create_image:: invalid JSON format" >&2
			return 1
		fi
	fi

	local slack_file_json=""
	if [[ "$has_slack_file" == true ]]; then
		if ! slack_file_json=$(jq -r '.slack_file' <<<"$input"); then
			echo "create_image:: invalid JSON format" >&2
			return 1
		fi
		if [[ -z "$slack_file_json" ]] || [[ "$slack_file_json" == "null" ]]; then
			echo "create_image:: slack_file field is required" >&2
			return 1
		fi
	fi

	if ! jq -e '.alt_text' <<<"$input" >/dev/null 2>&1; then
		echo "create_image:: alt_text field is required" >&2
		return 1
	fi

	local alt_text
	if ! alt_text=$(jq -r '.alt_text // empty' <<<"$input"); then
		echo "create_image:: invalid JSON format" >&2
		return 1
	fi
	if [[ -z "$alt_text" ]] || [[ "$alt_text" == "null" ]]; then
		echo "create_image:: alt_text field is required" >&2
		return 1
	fi

	if [[ "${#alt_text}" -gt "$MAX_ALT_TEXT_LENGTH" ]]; then
		echo "create_image:: alt_text must be $MAX_ALT_TEXT_LENGTH characters or less" >&2
		return 1
	fi

	local title_json=""
	if jq -e '.title' <<<"$input" >/dev/null 2>&1; then
		local title
		if ! title=$(jq -r '.title // empty' <<<"$input"); then
			echo "create_image:: invalid JSON format" >&2
			return 1
		fi
		if [[ -n "$title" ]] && [[ "$title" != "null" ]]; then
			local title_type
			if ! title_type=$(jq -r '.title.type // empty' <<<"$input"); then
				echo "create_image:: invalid JSON format" >&2
				return 1
			fi
			if [[ "$title_type" != "plain_text" ]]; then
				echo "create_image:: title type must be plain_text" >&2
				return 1
			fi

			local title_text
			if ! title_text=$(jq -r '.title.text // empty' <<<"$input"); then
				echo "create_image:: invalid JSON format" >&2
				return 1
			fi
			if [[ -z "$title_text" ]] || [[ "$title_text" == "null" ]]; then
				echo "create_image:: title.text field is required when title is present" >&2
				return 1
			fi

			if [[ "${#title_text}" -gt "$MAX_TITLE_TEXT_LENGTH" ]]; then
				echo "create_image:: title text must be $MAX_TITLE_TEXT_LENGTH characters or less" >&2
				return 1
			fi

			title_json=$(jq -r '.title' <<<"$input")
		fi
	fi

	local block_id=""
	if jq -e '.block_id' <<<"$input" >/dev/null 2>&1; then
		if ! block_id=$(jq -r '.block_id // empty' <<<"$input"); then
			echo "create_image:: invalid JSON format" >&2
			return 1
		fi
		if [[ -n "$block_id" ]] && [[ "$block_id" != "null" ]]; then
			if [[ "${#block_id}" -gt "$MAX_BLOCK_ID_LENGTH" ]]; then
				echo "create_image:: block_id must be $MAX_BLOCK_ID_LENGTH characters or less" >&2
				return 1
			fi
		fi
	fi

	local block
	if [[ "$has_image_url" == true ]]; then
		block=$(jq -n \
			--arg block_type "$BLOCK_TYPE" \
			--arg image_url "$image_url" \
			--arg alt_text "$alt_text" \
			'{ type: $block_type, image_url: $image_url, alt_text: $alt_text }')
	else
		block=$(jq -n \
			--arg block_type "$BLOCK_TYPE" \
			--arg alt_text "$alt_text" \
			--argjson slack_file "$slack_file_json" \
			'{ type: $block_type, slack_file: $slack_file, alt_text: $alt_text }')
	fi

	if [[ -n "$title_json" ]] && [[ "$title_json" != "null" ]]; then
		block=$(jq --argjson title "$title_json" '. + {title: $title}' <<<"$block")
	fi

	if [[ -n "$block_id" ]] && [[ "$block_id" != "null" ]]; then
		block=$(jq --arg block_id "$block_id" '. + {block_id: $block_id}' <<<"$block")
	fi

	echo "$block"

	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	create_image "$@"
fi
