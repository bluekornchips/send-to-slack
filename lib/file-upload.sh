#!/usr/bin/env bash
#
# File upload orchestration for Slack
# Coordinates the 3-step file upload process to Slack
# Ref: https://docs.slack.dev/messaging/working-with-files/#upload
#
set -eo pipefail
umask 077

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
#   Writes "unknown" if stat command fails or is unavailable, should never happen
#
# Returns:
#   0 on success
#   1 if file path is empty
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
#
# Ref: https://docs.slack.dev/messaging/working-with-files/#upload-step-1
#
# Side Effects:
# - Sets FILE_ID and UPLOAD_URL environment variables
#
_get_upload_url() {
	echo "_get_upload_url:: requesting upload URL from Slack API (filename=${FILENAME} size=${FILE_SIZE})" >&2

	local api_response
	if ! api_response=$(curl -s -X POST \
		-H "Authorization: Bearer ${SLACK_BOT_USER_OAUTH_TOKEN}" \
		-F "filename=${FILENAME}" \
		-F "length=${FILE_SIZE}" \
		--max-time 30 \
		--connect-timeout 10 \
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
_post_file_contents() {
	echo "_post_file_contents:: uploading file contents to Slack (path=${FILE_PATH} size=${FILE_SIZE})" >&2

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
	http_code=$(tail -n1 <<<"$http_response")

	local response_body
	response_body=$(sed '$d' <<<"$http_response")

	local response_size
	response_size="${response_body//OK - /}"

	if [[ "$http_code" != "200" ]]; then
		cat <<EOF >&2
_post_file_contents:: HTTP error ${http_code} from upload URL for file: ${FILE_PATH}
EOF
		if [[ -n "$response_body" ]]; then
			echo "_post_file_contents:: response body: ${response_body}" >&2
		fi
		return 1
	fi

	if ! grep -q "OK - " <<<"$response_body"; then
		echo "_post_file_contents:: unexpected response format from upload URL for file: $FILE_PATH" >&2
		echo "_post_file_contents:: response body: $response_body" >&2
		return 1
	fi

	# Verify file size matches
	echo "_post_file_contents:: file size verification: sent=$FILE_SIZE bytes, response=$response_size bytes" >&2
	if [[ "$response_size" != "$FILE_SIZE" ]]; then
		echo "_post_file_contents:: file size mismatch (sent: $FILE_SIZE, response: $response_size)" >&2
		echo "_post_file_contents:: response body: $response_body" >&2
		return 1
	fi

	echo "_post_file_contents:: file uploaded successfully, HTTP $http_code, size verified: $FILE_SIZE bytes" >&2
	return 0
}

# Step 3 of Slack file upload: Complete upload and share file.
#
# Calls files.completeUploadExternal API to finalize upload and optionally
# share the file to a channel. Supports channel name/ID resolution.
#
# Ref: https://docs.slack.dev/messaging/working-with-files/#upload-step-3
#
# Side Effects:
# - Outputs file metadata JSON on success
#
_complete_upload() {
	echo "_complete_upload:: finalizing upload via files.completeUploadExternal" >&2

	local api_response
	if ! api_response=$(curl -s -X POST \
		-H "Authorization: Bearer ${SLACK_BOT_USER_OAUTH_TOKEN}" \
		-H "Content-Type: application/json; charset=utf-8" \
		-d @"${UPLOAD_PAYLOAD_FILE}" \
		--max-time 30 \
		--connect-timeout 10 \
		"${API_URL}"); then
		echo "_complete_upload:: failed to complete upload: $api_response" >&2
		return 1
	fi

	if [[ -z "$api_response" ]]; then
		echo "_complete_upload:: empty response from Slack API" >&2
		return 1
	fi

	# Validate JSON response
	if ! jq -e . >/dev/null 2>&1 <<<"$api_response"; then
		echo "_complete_upload:: invalid JSON response from Slack API" >&2
		echo "_complete_upload:: response: $api_response" >&2
		return 1
	fi

	# Check for API success
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

	# LIMITATION: Currently only handles the first file from the API response
	# The Slack API supports multiple files, but this implementation processes only one
	# To support multiple files, iterate over .files[] array and process each file
	local files_count
	files_count=$(jq '.files | length' <<<"$api_response")
	echo "_complete_upload:: files count in response: $files_count" >&2

	local first_file
	first_file=$(jq '.files[0]' <<<"$api_response")

	if [[ -z "$first_file" || "$first_file" == "null" ]]; then
		cat <<EOF >&2
_complete_upload:: missing files in Slack response
response:
$(jq -r '.' <<<"${api_response}")
EOF
		return 1
	fi

	# Debug file metadata
	local file_id file_size file_name file_type permalink mimetype media_display_type
	file_id=$(jq -r '.id // "unknown"' <<<"$first_file")
	file_size=$(jq -r '.size // "unknown"' <<<"$first_file")
	file_name=$(jq -r '.name // "unknown"' <<<"$first_file")
	file_type=$(jq -r '.filetype // "unknown"' <<<"$first_file")
	permalink=$(jq -r '.permalink // "unknown"' <<<"$first_file")
	mimetype=$(jq -r '.mimetype // "unknown"' <<<"$first_file")
	media_display_type=$(jq -r '.media_display_type // "unknown"' <<<"$first_file")

	cat >&2 <<-EOF
		_complete_upload:: file details:
		_complete_upload::   id: $file_id
		_complete_upload::   name: $file_name
		_complete_upload::   size: $file_size bytes
		_complete_upload::   type: $file_type
		_complete_upload::   mimetype: $mimetype
		_complete_upload::   media_display_type: $media_display_type
		_complete_upload::   permalink: $permalink
	EOF

	if [[ -n "$FILE_PATH" && -f "$FILE_PATH" ]]; then
		local file_perms_after
		local file_readable
		file_perms_after=$(get_file_permissions "$FILE_PATH")
		file_readable=$([ -r "$FILE_PATH" ] && echo "yes" || echo "no")
		cat >&2 <<-EOF
			_complete_upload:: file permissions after upload: $file_perms_after
			_complete_upload:: original file path: $FILE_PATH
			_complete_upload:: original file size: $FILE_SIZE bytes
			_complete_upload:: file readable: $file_readable
		EOF
	fi

	# Verify file size matches what we uploaded
	if [[ "$file_size" != "unknown" && "$file_size" != "null" ]] && [[ "$file_size" != "$FILE_SIZE" ]]; then
		echo "_complete_upload:: WARNING: file size mismatch (uploaded: $FILE_SIZE, API reports: $file_size)" >&2
	fi

	echo "$first_file"

	return 0
}

# Create Block Kit blocks from uploaded file metadata
#
# Inputs:
# - Reads file metadata JSON from stdin (file object from files.completeUploadExternal)
#
# Side Effects:
# - Outputs Block Kit block JSON to stdout
#
# Returns:
# - 0 on successful block creation
# - 1 if input is invalid or missing required fields
#
# Ref: https://docs.slack.dev/reference/block-kit/composition-objects/slack-file-object/
# Ref: https://docs.slack.dev/reference/objects/file-object/
create_file_blocks() {
	local file_metadata
	file_metadata=$(cat)

	if [[ -z "$file_metadata" ]]; then
		echo "create_file_blocks:: file metadata is required" >&2
		return 1
	fi

	if ! jq -e . >/dev/null 2>&1 <<<"$file_metadata"; then
		echo "create_file_blocks:: file metadata must be valid JSON" >&2
		return 1
	fi

	local file_id
	local permalink
	local filename
	local filetype

	file_id=$(jq -r '.id // empty' <<<"$file_metadata")
	permalink=$(jq -r '.permalink // empty' <<<"$file_metadata")
	filename=$(jq -r '.name // "file"' <<<"$file_metadata")
	filetype=$(jq -r '.filetype // ""' <<<"$file_metadata")

	if [[ -z "$file_id" || "$file_id" == "null" ]]; then
		echo "create_file_blocks:: file metadata missing id field" >&2
		return 1
	fi

	# Create appropriate block based on file type (per Slack's file object recommendations)
	if [[ "$filetype" =~ ^(png|jpg|jpeg|gif)$ ]]; then
		# For images: use image block with slack_file object
		local image_block
		image_block=$(jq -n \
			--arg file_id "$file_id" \
			'{
				type: "image",
				slack_file: {
					id: $file_id
				}
			}')

		echo "[$image_block]"
	else
		# For non-image files: use section block with markdown link
		local file_link_text
		if [[ -n "$permalink" ]]; then
			file_link_text="<${permalink}|${filename}>"
		else
			file_link_text="$filename"
		fi

		local section_block
		section_block=$(jq -n \
			--arg text "$file_link_text" \
			'{ type: "section",
				text: {
					type: "mrkdwn",
					text: $text
				}
			}')

		echo "[$section_block]"
	fi

	return 0
}

# Validate and extract file upload input configuration
#
# Arguments:
#   $1 - input_json: JSON string with file configuration
#
# Side Effects:
#   Sets FILE_PATH, FILENAME, FILE_SIZE, title, output_var
#   Exports FILENAME, FILE_SIZE, and output_var if specified
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
	if [[ ! -f "$FILE_PATH" ]]; then
		echo "file_upload:: file not found: $FILE_PATH" >&2
		return 1
	fi

	if ! head -c 1 "$FILE_PATH" >/dev/null 2>&1; then
		echo "file_upload:: file not readable: $FILE_PATH (check permissions)" >&2
		return 1
	fi

	FILENAME="${FILE_PATH##*/}"
	FILE_SIZE=$(stat -c%s "$FILE_PATH" 2>/dev/null || stat -f%z "$FILE_PATH" 2>/dev/null)

	if [[ -z "$FILE_SIZE" || ! "$FILE_SIZE" =~ ^[0-9]+$ ]]; then
		echo "file_upload:: unable to determine file size for: $FILE_PATH" >&2
		return 1
	fi

	local file_perms
	file_perms=$(get_file_permissions "$FILE_PATH")
	echo "file_upload:: file permissions: $file_perms" >&2

	if ((FILE_SIZE > MAX_FILE_SIZE)); then
		echo "file_upload:: file size ($FILE_SIZE bytes) exceeds Slack's maximum of $MAX_FILE_SIZE bytes: $FILE_PATH" >&2
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
# Side Effects:
#   Sets title and output_var
#   Exports output_var if specified
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
	output_var=$(jq -r '.interpolate_file_contents_to_var // empty' <<<"$file_config")
	if [[ -n "$output_var" ]]; then
		echo "extract_file_metadata:: reading file contents for variable interpolation (path=${FILE_PATH})" >&2
		local file_contents
		file_contents=$(cat "$FILE_PATH")
		export "$output_var"="$file_contents"
	fi

	echo "$title"
	return 0
}

# Validate required environment variables for file upload
#
# Returns:
#   0 if all required variables are set and valid
#   1 if any required variable is missing or invalid
validate_upload_environment() {
	if [[ -z "$CHANNEL" ]]; then
		echo "file_upload:: CHANNEL environment variable is required" >&2
		return 1
	fi

	# Validate channel ID format (basic check)
	# Supports: C (public), G (private/groups), D (direct), Z (shared) IDs
	# Also allows channel names (alphanumeric with hyphens/underscores)
	if [[ ! "$CHANNEL" =~ ^[CGDZ][A-Z0-9]{8,}$ ]] && [[ ! "$CHANNEL" =~ ^[a-zA-Z0-9_-]+$ ]]; then
		cat >&2 <<-EOF
			file_upload:: invalid channel format: $CHANNEL
			file_upload:: channel must be a valid Slack ID (C/G/D/Z prefix) or channel name
		EOF
		return 1
	fi

	if [[ -z "${SLACK_BOT_USER_OAUTH_TOKEN}" ]]; then
		echo "file_upload:: SLACK_BOT_USER_OAUTH_TOKEN environment variable is required" >&2
		return 1
	fi

	return 0
}

# Orchestrate the complete 3-step file upload process
#
# Inputs:
# - JSON from stdin with structure:
#   {
#     "file": {
#       "path": "{path to file}", // required
#       "title": "{title of file}", // optional, defaults to basename
#       "text": "{text to include with file}", // optional, defaults to filename
#       "interpolate-file-contents": "{variable name}" // optional
#     }
#   }
#
# Side Effects:
# - Uploads file to Slack via 3-step process
# - Outputs rich_text block JSON to stdout on success
#
# Returns:
# - 0 on successful upload and share
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

	echo "file_upload:: starting upload (path=${FILE_PATH} size=${FILE_SIZE} bytes)" >&2

	if [[ "${LOG_VERBOSE:-}" == "true" ]]; then
		echo "file_upload:: filename: ${FILENAME}" >&2
	fi

	local title
	if ! title=$(extract_file_metadata "$file_config"); then
		return 1
	fi

	echo "file_upload:: file title: $title" >&2

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

	local upload_payload_file
	upload_payload_file=$(mktemp /tmp/file-upload.sh.payload.XXXXXX)
	if ! chmod 0600 "$upload_payload_file"; then
		echo "file_upload:: failed to secure upload payload file ${upload_payload_file}" >&2
		rm -f "$upload_payload_file"
		return 1
	fi
	trap 'rm -f "$upload_payload_file"' RETURN EXIT ERR

	jq -n \
		--arg file_id "$FILE_ID" \
		--arg title "$title" \
		'{ files: [{
				id: $file_id,
				title: $title
			}]
		}' >"$upload_payload_file"

	echo "file_upload:: complete upload payload:" >&2
	jq . <"$upload_payload_file" >&2

	API_URL="https://slack.com/api/files.completeUploadExternal?channel_id=${CHANNEL}"
	export API_URL
	export UPLOAD_PAYLOAD_FILE="$upload_payload_file"

	local file_metadata
	if ! file_metadata=$(_complete_upload); then
		return 1
	fi

	local rich_text_block
	local permalink
	local file_id_from_metadata
	local file_size_from_metadata
	file_id_from_metadata=$(jq -r '.id // "unknown"' <<<"$file_metadata")
	file_size_from_metadata=$(jq -r '.size // "unknown"' <<<"$file_metadata")
	permalink=$(jq -r '.permalink // empty' <<<"$file_metadata")

	echo "file_upload:: upload complete, file_id: $file_id_from_metadata permalink: $permalink" >&2
	echo "file_upload:: file metadata:" >&2
	echo "$file_metadata" | jq . >&2

	if [[ -z "$permalink" || "$permalink" == "null" || "$permalink" == "empty" ]]; then
		echo "file_upload:: failed to get permalink from uploaded file: $FILE_PATH (file_id: $file_id_from_metadata)" >&2
		return 1
	fi

	# Create rich_text with file link
	rich_text_block=$(jq -n \
		--arg link "$permalink" \
		--arg filename "$FILENAME" \
		'{
			type: "rich_text",
			elements: [
				{
					type: "rich_text_section",
					elements: [
						{ type: "link", url: $link, text: $filename }
					]
				}
			]
		}')

	echo "$rich_text_block"

	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	file_upload "$@"
	exit $?
fi
