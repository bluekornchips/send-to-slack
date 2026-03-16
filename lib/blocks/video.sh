#!/usr/bin/env bash
#
# Video Block implementation following Slack Block Kit guidelines
# Ref: https://docs.slack.dev/reference/block-kit/blocks/video-block/
#

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

########################################################
# Example Strings
########################################################
EXAMPLE_VIDEO_BLOCK='{"video_url": "https://www.youtube.com/embed/pWTSK5waNs8", "thumbnail_url": "https://i.ytimg.com/vi/pWTSK5waNs8/hqdefault.jpg", "alt_text": "Example video", "title": {"type": "plain_text", "text": "Example Video"}}'

# Read optional string field from input JSON. Outputs value to stdout, empty if absent or null.
# Returns 1 on validation error (e.g. over max length).
# Arguments: $1 input JSON, $2 jq path, $3 field name for errors, $4 optional max length.
_video_optional_string() {
	local input="$1"
	local jq_path="$2"
	local field_name="$3"
	local max_len="${4:-}"
	local val

	if ! jq . <<<"$input" >/dev/null 2>&1; then
		echo "create_video:: invalid JSON format" >&2
		return 1
	fi

	if ! jq -e "$jq_path" <<<"$input" >/dev/null 2>&1; then
		echo ""
		return 0
	fi

	if ! val=$(jq -r "$jq_path // empty" <<<"$input"); then
		echo "create_video:: invalid JSON format" >&2
		return 1
	fi

	if [[ -z "$val" ]] || [[ "$val" == "null" ]]; then
		echo ""
		return 0
	fi

	if [[ -n "$max_len" ]] && [[ "${#val}" -gt "$max_len" ]]; then
		echo "create_video:: ${field_name} must be ${max_len} characters or less" >&2
		return 1

	fi

	echo "$val"

	return 0
}

# Read optional description object from input JSON. Outputs jq .description to stdout if valid.
# Outputs nothing if absent. Returns 1 on validation error.
_video_optional_description() {
	local input="$1"
	if ! jq -e '.description' <<<"$input" >/dev/null 2>&1; then
		return 0
	fi

	local description_type
	description_type=$(jq -r '.description.type // empty' <<<"$input")
	if [[ "$description_type" != "plain_text" ]]; then
		echo "create_video:: description type must be plain_text" >&2
		return 1
	fi

	local description_text
	description_text=$(jq -r '.description.text // empty' <<<"$input")
	if [[ -z "$description_text" ]] || [[ "$description_text" == "null" ]]; then
		echo "create_video:: description.text field is required when description is present" >&2
		return 1
	fi

	if [[ "${#description_text}" -gt "$MAX_DESCRIPTION_TEXT_LENGTH" ]]; then
		echo "create_video:: description text must be $MAX_DESCRIPTION_TEXT_LENGTH characters or less" >&2
		return 1
	fi

	jq '.description' <<<"$input"

	return 0
}

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
		echo "create_video:: Example: $EXAMPLE_VIDEO_BLOCK" >&2
		return 1
	fi

	local video_url
	if ! video_url=$(jq -r '.video_url // empty' <<<"$input"); then
		echo "create_video:: invalid JSON format" >&2
		return 1
	fi

	if [[ -z "$video_url" ]] || [[ "$video_url" == "null" ]]; then
		echo "create_video:: video_url field is required and cannot be empty" >&2
		echo "create_video:: Example: $EXAMPLE_VIDEO_BLOCK" >&2
		return 1
	fi

	if ! jq -e '.thumbnail_url' <<<"$input" >/dev/null 2>&1; then
		echo "create_video:: thumbnail_url field is required" >&2
		echo "create_video:: Example: $EXAMPLE_VIDEO_BLOCK" >&2
		return 1
	fi

	local thumbnail_url
	if ! thumbnail_url=$(jq -r '.thumbnail_url // empty' <<<"$input"); then
		echo "create_video:: invalid JSON format" >&2
		return 1
	fi

	if [[ -z "$thumbnail_url" ]] || [[ "$thumbnail_url" == "null" ]]; then
		echo "create_video:: thumbnail_url field is required and cannot be empty" >&2
		echo "create_video:: Example: $EXAMPLE_VIDEO_BLOCK" >&2
		return 1
	fi

	if ! jq -e '.alt_text' <<<"$input" >/dev/null 2>&1; then
		echo "create_video:: alt_text field is required" >&2
		echo "create_video:: Example: $EXAMPLE_VIDEO_BLOCK" >&2
		return 1
	fi

	local alt_text
	if ! alt_text=$(jq -r '.alt_text // empty' <<<"$input"); then
		echo "create_video:: invalid JSON format" >&2
		return 1
	fi

	if [[ -z "$alt_text" ]] || [[ "$alt_text" == "null" ]]; then
		echo "create_video:: alt_text field is required and cannot be empty" >&2
		echo "create_video:: Example: $EXAMPLE_VIDEO_BLOCK" >&2
		return 1
	fi

	if [[ "${#alt_text}" -gt "$MAX_ALT_TEXT_LENGTH" ]]; then
		echo "create_video:: alt_text must be $MAX_ALT_TEXT_LENGTH characters or less" >&2
		return 1
	fi

	if ! jq -e '.title' <<<"$input" >/dev/null 2>&1; then
		echo "create_video:: title field is required" >&2
		echo "create_video:: Example: $EXAMPLE_VIDEO_BLOCK" >&2
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
		echo "create_video:: title.text field is required and cannot be empty" >&2
		echo "create_video:: Example: $EXAMPLE_VIDEO_BLOCK" >&2
		return 1
	fi

	if [[ "${#title_text}" -gt "$MAX_TITLE_TEXT_LENGTH" ]]; then
		echo "create_video:: title text must be $MAX_TITLE_TEXT_LENGTH characters or less" >&2
		return 1
	fi

	local title_json
	title_json=$(jq '.title' <<<"$input")

	local title_url
	title_url=$(_video_optional_string "$input" '.title_url' 'title_url') || return 1

	local description_json
	description_json=$(_video_optional_description "$input") || return 1

	local author_name
	author_name=$(_video_optional_string "$input" '.author_name' 'author_name' "$MAX_AUTHOR_NAME_LENGTH") || return 1

	local provider_name
	provider_name=$(_video_optional_string "$input" '.provider_name' 'provider_name' "$MAX_PROVIDER_NAME_LENGTH") || return 1

	local provider_icon_url
	provider_icon_url=$(_video_optional_string "$input" '.provider_icon_url' 'provider_icon_url') || return 1

	local block_id
	block_id=$(_video_optional_string "$input" '.block_id' 'block_id' "$MAX_BLOCK_ID_LENGTH") || return 1

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
	set -eo pipefail
	umask 077
	create_video "$@"
	exit $?
fi
