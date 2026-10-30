#!/usr/bin/env bash
#
# File upload orchestration for Slack
# Steps 1-2 upload bytes. files.completeUploadExternal shares into a channel
# at send time so sibling blocks ride on the same snippet message.
# Ref: https://docs.slack.dev/messaging/working-with-files/#upload
#

# Validate file size against Slack's 1 GB limit
# Ref: https://docs.slack.dev/messaging/working-with-files
MAX_FILE_SIZE=$((1024 * 1024 * 1024)) # 1 GB in bytes

# Get file permissions
#
# Arguments:
#   $1 - file_path: Path to file
#
# Outputs:
#   Writes file permissions to stdout
# Writes "unknown" if stat command fails or is unavailable, should never happen
#
# Returns:
#   0 on success
#   1 if file path is empty or stat fails
get_file_permissions() {
	local file_path="$1"

	if [[ -z "$file_path" ]]; then
		echo "unknown"
		return 1
	fi

	if stat -c "%a %A" "$file_path" 2>/dev/null; then
		return 0
	elif stat -f "%OLp %Sp" "$file_path" 2>/dev/null; then
		return 0
	else
		echo "unknown"
		return 1
	fi
}

# Step 1 of Slack file upload: Request upload URL
# Calls files.getUploadURLExternal API to obtain upload URL and file ID
# Sends snippet_type=markdown when FILENAME ends in .md or .markdown
#
# Ref: https://docs.slack.dev/messaging/working-with-files/#upload-step-1
#
# Side Effects:
# - Sets FILE_ID and UPLOAD_URL environment variables
#
# Returns:
#   0 on success
#   1 on API or parse failure
_get_upload_url() {

	local curl_args
	curl_args=(
		-s -X POST
		-H "Authorization: Bearer ${SLACK_BOT_USER_OAUTH_TOKEN}"
		-F "filename=${FILENAME}"
		-F "length=${FILE_SIZE}"
		--max-time 30
		--connect-timeout 10
	)

	local lower_name
	lower_name=$(printf '%s' "$FILENAME" | tr '[:upper:]' '[:lower:]')
	if [[ "$lower_name" == *.md || "$lower_name" == *.markdown ]]; then
		curl_args+=(-F "snippet_type=markdown")
	fi

	local api_response
	if ! api_response=$(curl "${curl_args[@]}" \
		"https://slack.com/api/files.getUploadURLExternal"); then
		echo "_get_upload_url:: failed to get upload URL: $api_response" >&2
		return 1
	fi

	if ! jq -e . >/dev/null 2>&1 <<<"$api_response"; then
		echo "_get_upload_url:: invalid JSON response from Slack API" >&2
		echo "_get_upload_url:: response: $api_response" >&2
		return 1
	fi

	local ok
	if ! ok=$(jq -r '.ok // false' <<<"$api_response"); then
		cat <<EOF >&2
_get_upload_url:: failed to get ok from Slack API
response:
$(jq -r '.' <<<"${api_response}")
EOF
		return 1
	fi

	if [[ "$ok" != "true" ]]; then
		local error
		error=$(jq -r '.error // ""' <<<"$api_response")
		cat <<EOF >&2
_get_upload_url:: Slack API error: ${error}
response:
$(jq -r '.' <<<"${api_response}")
EOF
		return 1
	fi

	local upload_url
	if ! upload_url=$(jq -r '.upload_url // empty' <<<"$api_response"); then
		echo "_get_upload_url:: failed to get upload URL from Slack API" >&2
		return 1
	fi

	if [[ -z "$upload_url" ]]; then
		echo "_get_upload_url:: missing upload URL in Slack response" >&2
		return 1
	fi

	local file_id
	if ! file_id=$(jq -r '.file_id // empty' <<<"$api_response"); then
		echo "_get_upload_url:: failed to get file ID from Slack API" >&2
		return 1
	fi

	FILE_ID="$file_id"
	UPLOAD_URL="$upload_url"

	export FILE_ID
	export UPLOAD_URL

	return 0
}

# Step 2 of Slack file upload: Post file contents
# Uploads the actual file data to the URL provided by Step 1
#
# Ref: https://docs.slack.dev/messaging/working-with-files/#upload-step-2
#
# Returns:
#   0 on success
#   1 on HTTP or size verification failure
_post_file_contents() {

	local http_response
	if ! http_response=$(curl -s -w "\n%{http_code}" \
		-H "Content-Type: application/octet-stream" \
		--data-binary "@${FILE_PATH}" \
		--max-time 60 \
		--connect-timeout 10 \
		"$UPLOAD_URL"); then
		echo "_post_file_contents:: failed to post file contents: $http_response" >&2
		return 1
	fi

	local http_code
	http_code=$(sed -n '$p' <<<"$http_response")
	local response_body
	response_body=$(sed '$d' <<<"$http_response")

	local response_size
	response_size="${response_body//OK - /}"

	if [[ "$http_code" != "200" ]]; then
		cat <<EOF >&2
_post_file_contents:: HTTP error ${http_code} from upload URL for file:
${FILE_PATH}
EOF
		if [[ -n "$response_body" ]]; then
			echo "_post_file_contents:: response body: ${response_body}" >&2
		fi
		return 1
	fi

	if ! grep -q "OK - " <<<"$response_body"; then
		echo "_post_file_contents:: unexpected response format from upload URL for file:
$FILE_PATH" >&2
		echo "_post_file_contents:: response body: $response_body" >&2
		return 1
	fi

	echo "_post_file_contents:: file size verification: sent=$FILE_SIZE bytes,
response=$response_size bytes" >&2
	if [[ "$response_size" != "$FILE_SIZE" ]]; then
		echo "_post_file_contents:: file size mismatch (sent: $FILE_SIZE, response:
$response_size)" >&2
		echo "_post_file_contents:: response body: $response_body" >&2
		return 1
	fi

	echo "_post_file_contents:: file uploaded successfully, HTTP $http_code, size
verified: $FILE_SIZE bytes" >&2
	return 0
}

# Extract channel and ts from a complete-upload response for permalink lookup.
#
# Arguments:
#   $1 - api_response: JSON body from files.completeUploadExternal
#   $2 - channel_id: Channel ID sent in the complete-upload request
#
# Outputs:
#   Writes JSON with channel and ts fields merged onto api_response
#
# Returns:
#   0 on success
#   1 if jq fails
_normalize_complete_upload_response() {
	local api_response="$1"
	local channel_id="$2"

	if [[ -z "$api_response" ]]; then
		echo "_normalize_complete_upload_response:: api_response is required" >&2
		return 1
	fi

	if [[ -z "$channel_id" ]]; then
		echo "_normalize_complete_upload_response:: channel_id is required" >&2
		return 1
	fi

	jq -c --arg ch "$channel_id" '
		. + {
			channel: (
				.channel
				// .files[0].channels[0]
				// $ch
			),
			ts: (
				.ts
				// .files[0].shares.public[$ch][0].ts
				// .files[0].shares.private[$ch][0].ts
				// empty
			)
		}
	' <<<"$api_response"

	return 0
}

# Step 3 of Slack file upload: complete upload and share into a channel.
#
# Calls files.completeUploadExternal as multipart form fields. channel_id must
# be in the body. Slack ignores channel_id on the query string for JSON POSTs.
# Do not set initial_comment; Slack drops blocks when that field is present.
#
# Ref: https://docs.slack.dev/messaging/working-with-files/#upload-step-3
#
# Arguments:
#   $1 - files_json: JSON array of {id, title} objects
#   $2 - channel_id: resolved Slack channel ID
#   $3 - blocks_json: Block Kit array JSON, empty or [] to omit
#   $4 - thread_ts: optional thread timestamp
#   $5 - username: optional bot username
#   $6 - icon_emoji: optional icon emoji
#   $7 - icon_url: optional icon URL
#
# Side Effects:
# - Sets SLACK_LAST_RESPONSE to the API body with channel and ts when found
#
# Returns:
#   0 on success
#   1 on validation or API failure
_complete_upload() {
	local files_json="$1"
	local channel_id="$2"
	local blocks_json="${3:-}"
	local thread_ts="${4:-}"
	local username="${5:-}"
	local icon_emoji="${6:-}"
	local icon_url="${7:-}"

	if [[ -z "$files_json" ]]; then
		echo "_complete_upload:: files_json is required" >&2
		return 1
	fi

	if [[ -z "$channel_id" ]]; then
		echo "_complete_upload:: channel_id is required" >&2
		return 1
	fi

	local curl_args
	curl_args=(
		-s -X POST
		-H "Authorization: Bearer ${SLACK_BOT_USER_OAUTH_TOKEN}"
		-F "files=${files_json}"
		-F "channel_id=${channel_id}"
		--max-time 30
		--connect-timeout 10
	)

	if [[ -n "$blocks_json" && "$blocks_json" != "[]" &&
		"$blocks_json" != "null" ]]; then
		curl_args+=(-F "blocks=${blocks_json}")
	fi

	if [[ -n "$thread_ts" && "$thread_ts" != "null" ]]; then
		curl_args+=(-F "thread_ts=${thread_ts}")
	fi

	if [[ -n "$username" ]]; then
		curl_args+=(-F "username=${username}")
	fi
	if [[ -n "$icon_emoji" ]]; then
		curl_args+=(-F "icon_emoji=${icon_emoji}")
	fi
	if [[ -n "$icon_url" ]]; then
		curl_args+=(-F "icon_url=${icon_url}")
	fi

	local api_response
	if ! api_response=$(curl "${curl_args[@]}" \
		"https://slack.com/api/files.completeUploadExternal"); then
		echo "_complete_upload:: failed to complete upload: $api_response" >&2
		return 1
	fi

	if [[ -z "$api_response" ]]; then
		echo "_complete_upload:: empty response from Slack API" >&2
		return 1
	fi

	if ! jq -e . >/dev/null 2>&1 <<<"$api_response"; then
		echo "_complete_upload:: invalid JSON response from Slack API" >&2
		echo "_complete_upload:: response: $api_response" >&2
		return 1
	fi

	local ok
	ok=$(jq -r '.ok // false' <<<"$api_response")
	if [[ "$ok" != "true" ]]; then
		cat <<EOF >&2
_complete_upload:: Slack API error:
response:
$(jq -r '.' <<<"${api_response}")
EOF
		return 1
	fi

	local files_count
	files_count=$(jq '.files | length' <<<"$api_response")
	echo "_complete_upload:: files count in response: $files_count" >&2

	if [[ "$files_count" == "0" || "$files_count" == "null" ]]; then
		cat <<EOF >&2
_complete_upload:: missing files in Slack response
response:
$(jq -r '.' <<<"${api_response}")
EOF
		return 1
	fi

	local normalized
	if ! normalized=$(_normalize_complete_upload_response \
		"$api_response" "$channel_id"); then
		return 1
	fi

	SLACK_LAST_RESPONSE="$normalized"
	export SLACK_LAST_RESPONSE

	return 0
}

# Validate and extract file upload input configuration
#
# Arguments:
#   $1 - input_json: JSON string with file configuration
#
# Side Effects:
#   Sets FILE_PATH
#
# Returns:
#   0 on successful validation
#   1 if validation fails
validate_file_upload_input() {
	local input_json="$1"

	if [[ -z "$input_json" ]]; then
		echo "file_upload:: input JSON is required on stdin" >&2
		return 1
	fi

	if ! jq -e . >/dev/null 2>&1 <<<"$input_json"; then
		echo "file_upload:: input must be valid JSON" >&2
		return 1
	fi

	local file_config
	file_config=$(jq '.file // .' <<<"$input_json")

	if [[ -z "$file_config" || "$file_config" == "null" ]]; then
		echo "file_upload:: file configuration is required" >&2
		return 1
	fi

	FILE_PATH=$(jq -r '.path // empty' <<<"$file_config")
	if [[ -z "$FILE_PATH" ]]; then
		echo "file_upload:: file.path is required" >&2
		return 1
	fi

	return 0
}

# Validate file path exists and is readable
#
# Side Effects:
#   Sets FILENAME and FILE_SIZE
#   Exports FILENAME and FILE_SIZE
#
# Returns:
#   0 if file is valid
#   1 if file validation fails
validate_file_path() {
	# Expand glob patterns in FILE_PATH to a concrete path.
	# If the path contains a wildcard and matches exactly one file, use that file.
	# Multiple matches or zero matches are both treated as errors.
	if [[ "$FILE_PATH" == *"*"* || "$FILE_PATH" == *"?"* ]]; then
		local matched_files
		# shellcheck disable=SC2206 # We want to split the glob pattern into an array
		matched_files=(${FILE_PATH})

		if [[ ${#matched_files[@]} -eq 0 ]] || [[ ! -f "${matched_files[0]}" ]]; then
			echo "file_upload:: file not found: $FILE_PATH" >&2
			return 1
		fi

		if [[ ${#matched_files[@]} -gt 1 ]]; then
			echo "file_upload:: glob matched multiple files: $FILE_PATH" >&2
			return 1
		fi

		FILE_PATH="${matched_files[0]}"
	fi

	if [[ ! -f "$FILE_PATH" ]]; then
		echo "file_upload:: file not found: $FILE_PATH" >&2
		return 1
	fi

	if ! head -c 1 "$FILE_PATH" >/dev/null 2>&1; then
		echo "file_upload:: file not readable: $FILE_PATH (check permissions)" >&2
		return 1
	fi

	FILENAME="${FILE_PATH##*/}"
	FILE_SIZE=$(stat -c%s "$FILE_PATH" 2>/dev/null || stat -f%z "$FILE_PATH" \
		2>/dev/null)

	if [[ -z "$FILE_SIZE" || ! "$FILE_SIZE" =~ ^[0-9]+$ ]]; then
		echo "file_upload:: unable to determine file size for: $FILE_PATH" >&2
		return 1
	fi

	local file_perms
	file_perms=$(get_file_permissions "$FILE_PATH")
	echo "file_upload:: file permissions: $file_perms" >&2

	if ((FILE_SIZE > MAX_FILE_SIZE)); then
		return 1
	fi

	export FILENAME
	export FILE_SIZE

	return 0
}

# Extract file metadata and optional configuration
#
# Arguments:
#   $1 - file_config: JSON string with file configuration
#
# Outputs:
#   Writes the display title to stdout
#
# Side Effects:
#   Exports the env var named by interpolate_file_contents_to_var
#
# Returns:
#   0 on success
extract_file_metadata() {
	local file_config="$1"

	local title
	title=$(jq -r '.title // empty' <<<"$file_config")
	if [[ -z "$title" ]]; then
		title="${FILE_PATH##*/}"
	fi

	local output_var
	output_var=$(jq -r '.interpolate_file_contents_to_var // empty' \
		<<<"$file_config")
	if [[ -n "$output_var" ]]; then
		local file_contents
		file_contents=$(cat "$FILE_PATH")
		export "$output_var"="$file_contents"
	fi

	echo "$title"
	return 0
}

# Validate required environment variables for byte upload, steps 1-2.
# Channel is not required here. Sharing happens in share_uploaded_files.
#
# Returns:
#   0 if the bot token is set
#   1 if the bot token is missing
validate_upload_environment() {
	if [[ -z "${SLACK_BOT_USER_OAUTH_TOKEN}" ]]; then
		echo "file_upload:: SLACK_BOT_USER_OAUTH_TOKEN environment variable is required" >&2
		return 1
	fi

	return 0
}

# Upload file bytes, steps 1-2. Sharing is share_uploaded_files at send time.
#
# Inputs:
# - JSON from stdin with structure:
#   {
#     "file": {
#       "path": "{path to file}",
#       "title": "{title of file}",
#       "interpolate_file_contents_to_var": "{variable name}"
#     }
#   }
#
# Side Effects:
# - Uploads file bytes to Slack unless DRY_RUN is true
# - Outputs {id, title, name} JSON to stdout on success
#
# Returns:
# - 0 on successful upload or dry-run
# - 1 if validation fails, file operations fail, or API calls fail
file_upload() {
	local input_json
	input_json=$(cat)

	if ! validate_file_upload_input "$input_json"; then
		return 1
	fi

	local file_config
	file_config=$(jq '.file // .' <<<"$input_json")

	if ! validate_file_path; then
		return 1
	fi

	if [[ "${LOG_VERBOSE:-}" == "true" ]]; then
		echo "file_upload:: filename: ${FILENAME}" >&2
	fi

	local title
	if ! title=$(extract_file_metadata "$file_config"); then
		return 1
	fi

	echo "file_upload:: file title: $title" >&2

	if [[ "${DRY_RUN:-}" == "true" ]]; then
		echo "file_upload:: DRY_RUN enabled, skipping Slack file upload" >&2
		if ! jq -nc \
			--arg id "F-DRY-RUN" \
			--arg title "$title" \
			--arg name "$FILENAME" \
			'{id: $id, title: $title, name: $name}'; then
			echo "file_upload:: failed to build metadata JSON" >&2
			return 1
		fi

		return 0
	fi

	if ! validate_upload_environment; then
		return 1
	fi

	if ! _get_upload_url; then
		return 1
	fi

	echo "file_upload:: upload URL obtained, file_id: $FILE_ID" >&2

	if ! _post_file_contents; then
		return 1
	fi

	if ! jq -nc \
		--arg id "$FILE_ID" \
		--arg title "$title" \
		--arg name "$FILENAME" \
		'{id: $id, title: $title, name: $name}'; then
		echo "file_upload:: failed to build metadata JSON" >&2
		return 1
	fi

	return 0
}

# Share uploaded files into a channel via files.completeUploadExternal.
#
# Sibling Block Kit on payload.blocks is sent as the blocks form field so the
# author line and the snippet card land on one message.
#
# Arguments:
#   $1 - payload: parsed Slack payload JSON with files array and channel
#
# Side Effects:
# - Resolves payload.channel to a channel ID
# - POSTs files.completeUploadExternal as multipart form fields
# - Sets SLACK_LAST_RESPONSE
#
# Returns:
#   0 on success
#   1 on validation or API failure
share_uploaded_files() {
	local payload="$1"

	if [[ -z "$payload" ]]; then
		echo "share_uploaded_files:: payload is required" >&2
		return 1
	fi

	if ! jq -e '.files | type == "array" and length > 0' >/dev/null 2>&1 \
		<<<"$payload"; then
		echo "share_uploaded_files:: payload.files must be a non-empty array" >&2
		return 1
	fi

	local channel
	channel=$(jq -r '.channel // empty' <<<"$payload")
	if [[ -z "$channel" || "$channel" == "null" ]]; then
		echo "share_uploaded_files:: payload.channel is required" >&2
		return 1
	fi

	local channel_id
	if ! channel_id=$(resolve_channel_id "$channel"); then
		echo "share_uploaded_files:: failed to resolve channel id" >&2
		return 1
	fi

	local files_json
	if ! files_json=$(jq -c \
		'[.files[] | {id: .id, title: (.title // .name // "")}]' \
		<<<"$payload"); then
		echo "share_uploaded_files:: failed to build files list" >&2
		return 1
	fi

	local blocks_json
	blocks_json=$(jq -c '.blocks // []' <<<"$payload")

	local thread_ts
	local username
	local icon_emoji
	local icon_url
	thread_ts=$(jq -r '.thread_ts // empty' <<<"$payload")
	username=$(jq -r '.username // empty' <<<"$payload")
	icon_emoji=$(jq -r '.icon_emoji // empty' <<<"$payload")
	icon_url=$(jq -r '.icon_url // empty' <<<"$payload")

	if ! _complete_upload "$files_json" "$channel_id" "$blocks_json" \
		"$thread_ts" "$username" "$icon_emoji" "$icon_url"; then
		return 1
	fi

	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	set -eo pipefail
	umask 077
	file_upload "$@"
	exit $?
fi
