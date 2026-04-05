#!/usr/bin/env bash
#
# Block creation and resolution for Slack Block Kit
# Dispatches block input JSON to the appropriate block script and post-processes the output
#

########################################################
# Files
########################################################

RICH_TEXT_BLOCK_FILE="lib/slack/block-kit/blocks/rich-text.sh"
TABLE_BLOCK_FILE="lib/slack/block-kit/blocks/table.sh"
SECTION_BLOCK_FILE="lib/slack/block-kit/blocks/section.sh"
HEADER_BLOCK_FILE="lib/slack/block-kit/blocks/header.sh"
CONTEXT_BLOCK_FILE="lib/slack/block-kit/blocks/context.sh"
DIVIDER_BLOCK_FILE="lib/slack/block-kit/blocks/divider.sh"
MARKDOWN_BLOCK_FILE="lib/slack/block-kit/blocks/markdown.sh"
ACTIONS_BLOCK_FILE="lib/slack/block-kit/blocks/actions.sh"
IMAGE_BLOCK_FILE="lib/slack/block-kit/blocks/image.sh"
VIDEO_BLOCK_FILE="lib/slack/block-kit/blocks/video.sh"

# Other scripts
FILE_UPLOAD_SCRIPT="lib/slack/utils/file-upload.sh"

########################################################
# Documentation URLs
########################################################

DOC_URL_BLOCK_KIT_ACTIONS="https://docs.slack.dev/reference/block-kit/blocks/actions-block"
DOC_URL_BLOCK_KIT_BLOCKS="https://docs.slack.dev/reference/block-kit/blocks"
DOC_URL_BLOCK_KIT_CONTEXT="https://docs.slack.dev/reference/block-kit/blocks/context-block"
DOC_URL_BLOCK_KIT_HEADER="https://docs.slack.dev/reference/block-kit/blocks/header-block"
DOC_URL_BLOCK_KIT_IMAGE="https://docs.slack.dev/reference/block-kit/blocks/image-block"
DOC_URL_BLOCK_KIT_MARKDOWN="https://docs.slack.dev/reference/block-kit/blocks/markdown-block"
DOC_URL_BLOCK_KIT_RICH_TEXT="https://docs.slack.dev/reference/block-kit/blocks/rich-text-block"
DOC_URL_BLOCK_KIT_SECTION="https://docs.slack.dev/reference/block-kit/blocks/section-block"
DOC_URL_BLOCK_KIT_VIDEO="https://docs.slack.dev/reference/block-kit/blocks/video-block"

# Find the repository root from this script's path, lib/slack/block-kit/create-block.sh
# Resolves symlinks with cd and pwd
#
# Outputs:
#   Writes root_dir path to stdout
#
# Returns:
#   0 on success
#   1 if root directory cannot be located
_find_root_dir() {
	local root_dir
	local script_path

	if [[ -z "${BASH_SOURCE[0]:-}" ]]; then
		echo "_find_root_dir:: BASH_SOURCE[0] is not set" >&2
		return 1
	fi

	# Get the absolute path of the directory containing this script
	script_path="${BASH_SOURCE[0]}"
	if [[ ! "$script_path" = /* ]]; then
		script_path=$(cd "$(dirname "$script_path")" && pwd)/$(basename "$script_path")
	fi

	local kit_dir
	local slack_dir
	local lib_dir

	kit_dir=$(cd "$(dirname "$script_path")" && pwd)
	if [[ -z "$kit_dir" ]]; then
		echo "_find_root_dir:: cannot determine block-kit directory" >&2
		return 1
	fi

	slack_dir=$(dirname "$kit_dir")
	if [[ -z "$slack_dir" ]] || [[ "$(basename "$slack_dir")" != "slack" ]]; then
		echo "_find_root_dir:: expected lib/slack/block-kit/create-block.sh under repository lib" >&2
		return 1
	fi

	lib_dir=$(dirname "$slack_dir")
	if [[ -z "$lib_dir" ]] || [[ "$(basename "$lib_dir")" != "lib" ]]; then
		echo "_find_root_dir:: expected create-block.sh under lib/slack/block-kit" >&2
		return 1
	fi

	root_dir=$(dirname "$lib_dir")
	if [[ -z "$root_dir" ]]; then
		echo "_find_root_dir:: cannot determine repository root from lib: ${lib_dir}" >&2
		return 1
	fi

	echo "$root_dir"

	return 0
}

# Resolve script path relative to root directory
#
# Arguments:
#   $1 - script_path: Relative path to script from root, lib/ layout
#
# Outputs:
#   Writes resolved absolute path to stdout
#
# Returns:
#   0 if script found
#   1 if script not found
_resolve_block_script_path() {
	local script_path="$1"
	local root_dir
	local full_path

	if ! root_dir=$(_find_root_dir); then
		return 1
	fi

	full_path="${root_dir}/${script_path}"
	if [[ -f "$full_path" ]]; then
		echo "$full_path"
		return 0
	fi

	return 1
}

# Validate that a block script file exists
#
# Arguments:
#   $1 - script_path: Relative path to script from root
#
# Returns:
#   0 if script exists
#   1 if script is missing
_validate_block_script() {
	local script_path="$1"
	local resolved_path

	if ! resolved_path=$(_resolve_block_script_path "$script_path"); then
		local root_dir
		root_dir=$(_find_root_dir 2>/dev/null || echo "unknown")
		echo "_validate_block_script:: block script not found: ${root_dir}/${script_path}" >&2
		return 1
	fi

	return 0
}

# Dispatch block input JSON to the appropriate block script, interpolate environment
# variables, filter empty values, and write the resulting block JSON to
# CREATE_BLOCK_OUTPUT_FILE.
#
# Arguments:
#   $1 - block_input: JSON string describing the block content
#   $2 - block_type: Slack Block Kit type, e.g. "section", "rich-text", "header"
#
# Side Effects:
#   Writes block JSON to CREATE_BLOCK_OUTPUT_FILE
#   Exports TABLE_BLOCK_OUTPUT_FILE when block_type is "table"
#   May export BUILD_PIPELINE_INSTANCE_VARS after JSON-escaping
#
# Returns:
#   0 on success
#   1 on validation or execution failure
create_block() {
	local block_input="$1"
	local block_type="$2"

	if [[ -z "${CREATE_BLOCK_OUTPUT_FILE:-}" ]]; then
		echo "create_block:: CREATE_BLOCK_OUTPUT_FILE is required" >&2
		return 1
	fi

	if [[ -z "$block_input" ]]; then
		echo "create_block:: input is required" >&2
		return 1
	fi

	if ! jq . >/dev/null 2>&1 <<<"$block_input"; then
		echo "create_block:: block_input must be valid JSON" >&2
		return 1
	fi

	local script_path=""

	case "$block_type" in
	"rich-text") script_path="$RICH_TEXT_BLOCK_FILE" ;;
	"table") script_path="$TABLE_BLOCK_FILE" ;;
	"section") script_path="$SECTION_BLOCK_FILE" ;;
	"header") script_path="$HEADER_BLOCK_FILE" ;;
	"context") script_path="$CONTEXT_BLOCK_FILE" ;;
	"divider") script_path="$DIVIDER_BLOCK_FILE" ;;
	"markdown") script_path="$MARKDOWN_BLOCK_FILE" ;;
	"actions") script_path="$ACTIONS_BLOCK_FILE" ;;
	"image") script_path="$IMAGE_BLOCK_FILE" ;;
	"video") script_path="$VIDEO_BLOCK_FILE" ;;
	"file") script_path="$FILE_UPLOAD_SCRIPT" ;;
	*)
		echo "create_block:: unsupported block type: $block_type. Skipping." >&2
		echo "create_block:: See supported block types: $DOC_URL_BLOCK_KIT_BLOCKS" >&2
		return 0
		;;
	esac

	if ! _validate_block_script "$script_path"; then
		return 1
	fi

	local resolved_script_path
	resolved_script_path=$(_resolve_block_script_path "$script_path")

	echo "create_block:: invoking block script: ${block_type} (${resolved_script_path})" >&2

	local script_exit_code=0
	if [[ "$block_type" == "table" ]]; then
		export TABLE_BLOCK_OUTPUT_FILE="$CREATE_BLOCK_OUTPUT_FILE"
		"$resolved_script_path" <<<"$block_input" || script_exit_code=$?
	else
		"$resolved_script_path" <<<"$block_input" >"$CREATE_BLOCK_OUTPUT_FILE" || script_exit_code=$?
	fi

	if [[ "$script_exit_code" -ne 0 ]]; then
		echo "create_block:: block script failed with exit code $script_exit_code" >&2
		case "$block_type" in
		"section")
			echo "create_block:: See section block docs: $DOC_URL_BLOCK_KIT_SECTION" >&2
			;;
		"header")
			echo "create_block:: See header block docs: $DOC_URL_BLOCK_KIT_HEADER" >&2
			;;
		"image")
			echo "create_block:: See image block docs: $DOC_URL_BLOCK_KIT_IMAGE" >&2
			;;
		"context")
			echo "create_block:: See context block docs: $DOC_URL_BLOCK_KIT_CONTEXT" >&2
			;;
		"markdown")
			echo "create_block:: See markdown block docs: $DOC_URL_BLOCK_KIT_MARKDOWN" >&2
			;;
		"rich-text")
			echo "create_block:: See rich text block docs: $DOC_URL_BLOCK_KIT_RICH_TEXT" >&2
			;;
		"actions")
			echo "create_block:: See actions block docs: $DOC_URL_BLOCK_KIT_ACTIONS" >&2
			;;
		"video")
			echo "create_block:: See video block docs: $DOC_URL_BLOCK_KIT_VIDEO" >&2
			;;
		esac
		return 1
	fi

	if [[ ! -s "$CREATE_BLOCK_OUTPUT_FILE" ]]; then
		echo "create_block:: block script produced no output" >&2
		return 1
	fi

	if ! jq . "$CREATE_BLOCK_OUTPUT_FILE" >/dev/null 2>&1; then
		echo "create_block:: block script output is not valid JSON" >&2
		echo "create_block:: output: $(cat "$CREATE_BLOCK_OUTPUT_FILE")" >&2
		return 1
	fi

	# JSON-escape BUILD_PIPELINE_INSTANCE_VARS if it contains JSON to prevent breaking JSON structure
	# Ref: https://concourse-ci.org/implementing-resource-types.html#resource-metadata
	if [[ -n "${BUILD_PIPELINE_INSTANCE_VARS}" ]] && [[ "$BUILD_PIPELINE_INSTANCE_VARS" =~ ^\{.*\}$ ]]; then
		local escaped_vars
		escaped_vars=$(echo "$BUILD_PIPELINE_INSTANCE_VARS" | jq -Rs . | sed 's/^"//;s/"$//;s/\\n$//')
		BUILD_PIPELINE_INSTANCE_VARS="$escaped_vars"
		export BUILD_PIPELINE_INSTANCE_VARS
	fi

	# Interpolate environment variables using $VAR syntax; write result back to the output file
	local interp_tmp
	interp_tmp=$(mktemp "$_SLACK_WORKSPACE/create_block.interp.XXXXXX")
	envsubst <"$CREATE_BLOCK_OUTPUT_FILE" | jq . >"$interp_tmp" && mv "$interp_tmp" "$CREATE_BLOCK_OUTPUT_FILE"

	local output_type
	output_type=$(jq -r 'if type == "array" then "array(\(length))" else .type // "unknown" end' "$CREATE_BLOCK_OUTPUT_FILE")
	echo "create_block:: resolved ${block_type} -> ${output_type}" >&2

	# Validate JSON after interpolation
	if ! jq . "$CREATE_BLOCK_OUTPUT_FILE" >/dev/null 2>&1; then
		echo "create_block:: failed to parse block after variable interpolation" >&2
		echo "create_block:: interpolated block:" >&2
		cat "$CREATE_BLOCK_OUTPUT_FILE" >&2
		return 1
	fi

	# Filter out empty values, null, empty strings, arrays, objects from all blocks
	local filter_tmp
	filter_tmp=$(mktemp "$_SLACK_WORKSPACE/create_block.filter.XXXXXX")
	jq \
		'walk(if . == null or . == "" or . == [] or . == {} or
			(type == "object" and .type == "text" and
				(.text == "" or .text == null)
			) then empty else . 
		end)
		' "$CREATE_BLOCK_OUTPUT_FILE" >"$filter_tmp" && mv "$filter_tmp" "$CREATE_BLOCK_OUTPUT_FILE"

	return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	set -eo pipefail
	umask 077
	exit 0
fi
