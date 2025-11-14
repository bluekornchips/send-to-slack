#!/usr/bin/env bash
#
# Video Block implementation following Slack Block Kit guidelines
# Ref: https://docs.slack.dev/reference/block-kit/blocks/video-block/
#
set -eo pipefail

########################################################
# Constants
########################################################
BLOCK_TYPE="video"
REQUIRED_TITLE_TYPE="plain_text"
MAX_ALT_TEXT_LENGTH=2000
MAX_TITLE_TEXT_LENGTH=2000
MAX_DESCRIPTION_TEXT_LENGTH=2000
MAX_AUTHOR_NAME_LENGTH=2000
MAX_PROVIDER_NAME_LENGTH=2000
MAX_BLOCK_ID_LENGTH=255

# Process video block and create Slack Block Kit video block format
#
# Inputs:
# - Reads JSON from stdin with video configuration
#
# Side Effects:
# - Outputs Slack Block Kit video block JSON to stdout
#
# Returns:
# - 0 on successful block creation with valid fields
# - 1 if input is empty, invalid JSON, or missing required fields
create_video() {
	local input
	input=$(cat)

	if [[ -z "$input" ]]; then
		echo "create_video:: input is required" >&2
		return 1
	fi

	if ! jq . >/dev/null 2>&1 <<<"$input"; then
		echo "create_video:: input must be valid JSON" >&2
		return 1
	fi

	if ! jq -e '.video_url' <<<"$input" >/dev/null 2>&1; then
		echo "create_video:: video_url field is required" >&2
		return 1
	fi

	local video_url
	if ! video_url=$(jq -r '.video_url // empty' <<<"$input"); then
		echo "create_video:: invalid JSON format" >&2
		return 1
	fi
	if [[ -z "$video_url" ]] || [[ "$video_url" == "null" ]]; then
		echo "create_video:: video_url field is required" >&2
		return 1
	fi

	if ! jq -e '.thumbnail_url' <<<"$input" >/dev/null 2>&1; then
		echo "create_video:: thumbnail_url field is required" >&2
		return 1
	fi

	local thumbnail_url
	if ! thumbnail_url=$(jq -r '.thumbnail_url // empty' <<<"$input"); then
		echo "create_video:: invalid JSON format" >&2
		return 1
	fi
	if [[ -z "$thumbnail_url" ]] || [[ "$thumbnail_url" == "null" ]]; then
		echo "create_video:: thumbnail_url field is required" >&2
		return 1
	fi

	if ! jq -e '.alt_text' <<<"$input" >/dev/null 2>&1; then
		echo "create_video:: alt_text field is required" >&2
		return 1
	fi

	local alt_text
	if ! alt_text=$(jq -r '.alt_text // empty' <<<"$input"); then
		echo "create_video:: invalid JSON format" >&2
		return 1
	fi
	if [[ -z "$alt_text" ]] || [[ "$alt_text" == "null" ]]; then
		echo "create_video:: alt_text field is required" >&2
		return 1
	fi

	if [[ "${#alt_text}" -gt "$MAX_ALT_TEXT_LENGTH" ]]; then
		echo "create_video:: alt_text must be $MAX_ALT_TEXT_LENGTH characters or less" >&2
		return 1
	fi

	if ! jq -e '.title' <<<"$input" >/dev/null 2>&1; then
		echo "create_video:: title field is required" >&2
		return 1
	fi

	local title_type
	if ! title_type=$(jq -r '.title.type // empty' <<<"$input"); then
		echo "create_video:: invalid JSON format" >&2
		return 1
	fi
	if [[ "$title_type" != "$REQUIRED_TITLE_TYPE" ]]; then
		echo "create_video:: title type must be $REQUIRED_TITLE_TYPE" >&2
		return 1
	fi

	local title_text
	if ! title_text=$(jq -r '.title.text // empty' <<<"$input"); then
		echo "create_video:: invalid JSON format" >&2
		return 1
	fi
	if [[ -z "$title_text" ]] || [[ "$title_text" == "null" ]]; then
		echo "create_video:: title.text field is required" >&2
		return 1
	fi

	if [[ "${#title_text}" -gt "$MAX_TITLE_TEXT_LENGTH" ]]; then
		echo "create_video:: title text must be $MAX_TITLE_TEXT_LENGTH characters or less" >&2
		return 1
	fi

	local title_json
	title_json=$(jq -r '.title' <<<"$input")

	local title_url=""
	if jq -e '.title_url' <<<"$input" >/dev/null 2>&1; then
		if ! title_url=$(jq -r '.title_url // empty' <<<"$input"); then
			echo "create_video:: invalid JSON format" >&2
			return 1
		fi
		if [[ -n "$title_url" ]] && [[ "$title_url" == "null" ]]; then
			title_url=""
		fi
	fi

	local description_json=""
	if jq -e '.description' <<<"$input" >/dev/null 2>&1; then
		local description
		if ! description=$(jq -r '.description // empty' <<<"$input"); then
			echo "create_video:: invalid JSON format" >&2
			return 1
		fi
		if [[ -n "$description" ]] && [[ "$description" != "null" ]]; then
			local description_type
			if ! description_type=$(jq -r '.description.type // empty' <<<"$input"); then
				echo "create_video:: invalid JSON format" >&2
				return 1
			fi
			if [[ "$description_type" != "plain_text" ]]; then
				echo "create_video:: description type must be plain_text" >&2
				return 1
			fi

			local description_text
			if ! description_text=$(jq -r '.description.text // empty' <<<"$input"); then
				echo "create_video:: invalid JSON format" >&2
				return 1
			fi
			if [[ -z "$description_text" ]] || [[ "$description_text" == "null" ]]; then
				echo "create_video:: description.text field is required when description is present" >&2
				return 1
			fi

			if [[ "${#description_text}" -gt "$MAX_DESCRIPTION_TEXT_LENGTH" ]]; then
				echo "create_video:: description text must be $MAX_DESCRIPTION_TEXT_LENGTH characters or less" >&2
				return 1
			fi

			description_json=$(jq -r '.description' <<<"$input")
		fi
	fi

	local author_name=""
	if jq -e '.author_name' <<<"$input" >/dev/null 2>&1; then
		if ! author_name=$(jq -r '.author_name // empty' <<<"$input"); then
			echo "create_video:: invalid JSON format" >&2
			return 1
		fi
		if [[ -n "$author_name" ]] && [[ "$author_name" != "null" ]]; then
			if [[ "${#author_name}" -gt "$MAX_AUTHOR_NAME_LENGTH" ]]; then
				echo "create_video:: author_name must be $MAX_AUTHOR_NAME_LENGTH characters or less" >&2
				return 1
			fi
		else
			author_name=""
		fi
	fi

	local provider_name=""
	if jq -e '.provider_name' <<<"$input" >/dev/null 2>&1; then
		if ! provider_name=$(jq -r '.provider_name // empty' <<<"$input"); then
			echo "create_video:: invalid JSON format" >&2
			return 1
		fi
		if [[ -n "$provider_name" ]] && [[ "$provider_name" != "null" ]]; then
			if [[ "${#provider_name}" -gt "$MAX_PROVIDER_NAME_LENGTH" ]]; then
				echo "create_video:: provider_name must be $MAX_PROVIDER_NAME_LENGTH characters or less" >&2
				return 1
			fi
		else
			provider_name=""
		fi
	fi

	local provider_icon_url=""
	if jq -e '.provider_icon_url' <<<"$input" >/dev/null 2>&1; then
		if ! provider_icon_url=$(jq -r '.provider_icon_url // empty' <<<"$input"); then
			echo "create_video:: invalid JSON format" >&2
			return 1
		fi
		if [[ -n "$provider_icon_url" ]] && [[ "$provider_icon_url" == "null" ]]; then
			provider_icon_url=""
		fi
	fi

	local block_id=""
	if jq -e '.block_id' <<<"$input" >/dev/null 2>&1; then
		if ! block_id=$(jq -r '.block_id // empty' <<<"$input"); then
			echo "create_video:: invalid JSON format" >&2
			return 1
		fi
		if [[ -n "$block_id" ]] && [[ "$block_id" != "null" ]]; then
			if [[ "${#block_id}" -gt "$MAX_BLOCK_ID_LENGTH" ]]; then
				echo "create_video:: block_id must be $MAX_BLOCK_ID_LENGTH characters or less" >&2
				return 1
			fi
		else
			block_id=""
		fi
	fi

	local block
	block=$(jq -n \
		--arg block_type "$BLOCK_TYPE" \
		--arg video_url "$video_url" \
		--arg thumbnail_url "$thumbnail_url" \
		--arg alt_text "$alt_text" \
		--argjson title "$title_json" \
		'{ type: $block_type, video_url: $video_url, thumbnail_url: $thumbnail_url, alt_text: $alt_text, title: $title }')

	if [[ -n "$title_url" ]] && [[ "$title_url" != "null" ]]; then
		block=$(jq --arg title_url "$title_url" '. + {title_url: $title_url}' <<<"$block")
	fi

	if [[ -n "$description_json" ]] && [[ "$description_json" != "null" ]]; then
		block=$(jq --argjson description "$description_json" '. + {description: $description}' <<<"$block")
	fi

	if [[ -n "$author_name" ]] && [[ "$author_name" != "null" ]]; then
		block=$(jq --arg author_name "$author_name" '. + {author_name: $author_name}' <<<"$block")
	fi

	if [[ -n "$provider_name" ]] && [[ "$provider_name" != "null" ]]; then
		block=$(jq --arg provider_name "$provider_name" '. + {provider_name: $provider_name}' <<<"$block")
	fi

	if [[ -n "$provider_icon_url" ]] && [[ "$provider_icon_url" != "null" ]]; then
		block=$(jq --arg provider_icon_url "$provider_icon_url" '. + {provider_icon_url: $provider_icon_url}' <<<"$block")
	fi

	if [[ -n "$block_id" ]] && [[ "$block_id" != "null" ]]; then
		block=$(jq --arg block_id "$block_id" '. + {block_id: $block_id}' <<<"$block")
	fi

	echo "$block"

	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	create_video "$@"
fi
