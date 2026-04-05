#!/usr/bin/env bash
#
# Payload loading, sanitization, validation, and delivery configuration
# Sources lib/parse/blocks.sh at end of file for process_blocks and full parse flow
#

if [[ -z "${SEND_TO_SLACK_ROOT:-}" ]]; then
	SEND_TO_SLACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
	export SEND_TO_SLACK_ROOT
fi

DEFAULT_DRY_RUN="false"

# Convert Slack permalink to thread_ts format if needed
#
# Arguments:
#   $1 - input: thread_ts value, may be permalink URL or timestamp
#
# Returns:
#   Outputs converted thread_ts to stdout
#   Returns original value if no 16-digit number found
#   0 on success
convert_thread_ts() {
	local input="$1"

	# Check if already in correct format (10 digits . 6 digits)
	if echo "$input" | grep -qE '^[0-9]{10}\.[0-9]{6}$'; then
		echo "$input"
		return 0
	fi

	# Extract 16-digit number and convert
	local timestamp
	timestamp=$(echo "$input" | grep -oE '[0-9]{16}' | sed -n '1p')

	if [[ -n "$timestamp" ]]; then
		# Convert format to insert decimal after 10 digits
		local seconds="${timestamp:0:10}"
		local microseconds="${timestamp:10}"

		echo "${seconds}.${microseconds}"

		return 0
	fi

	echo "$input"

	return 0
}

# Sanitize payload by redacting sensitive information, auth tokens, PII
#
# Arguments:
#   $1 - payload_json: JSON payload string to sanitize
#
# Outputs:
#   Writes sanitized JSON payload to stdout, token set to "[REDACTED]"
#
# Returns:
#   0 on success
#   1 if JSON is invalid
_sanitize_payload() {
	local payload_json="$1"

	if ! echo "$payload_json" | jq . >/dev/null 2>&1; then
		echo "$payload_json"
		return 1
	fi

	# Redact sensitive fields from source (auth tokens)
	# Set slack_bot_user_oauth_token to "[REDACTED]"
	local sanitized
	sanitized=$(echo "$payload_json" | jq '
		if .source then
			.source.slack_bot_user_oauth_token = "[REDACTED]"
		else
			.
		end
	')

	echo "$sanitized"
	return 0
}

# Log sanitized payload for debugging
#
# Uses global variable: INPUT_PAYLOAD
#
# Side Effects:
#   Writes sanitized payload to stderr for debugging
#
# Returns:
#   0 on success
#   1 if payload file is missing or cannot be read
_log_sanitized_payload() {
	if [[ ! -f "$INPUT_PAYLOAD" ]]; then
		echo "parse_payload:: payload file not found: $INPUT_PAYLOAD" >&2
		return 1
	fi

	local payload_content
	if ! payload_content=$(cat "$INPUT_PAYLOAD" 2>/dev/null); then
		echo "parse_payload:: failed to read payload file: $INPUT_PAYLOAD" >&2
		return 1
	fi

	local sanitized
	if ! sanitized=$(_sanitize_payload "$payload_content"); then
		echo "parse_payload:: failed to sanitize payload for logging" >&2
		return 1
	fi

	cat <<EOF >&2
parse_payload:: input payload (sanitized):
$(echo "$sanitized" | jq .)
EOF

	return 0
}

# Validate that input payload file contains valid JSON
#
# Uses global variable: INPUT_PAYLOAD
#
# Returns:
#   0 if valid JSON
#   1 if invalid JSON
validate_input_payload_json() {
	if [[ ! -f "$INPUT_PAYLOAD" ]]; then
		echo "validate_input_payload_json:: payload file not found: $INPUT_PAYLOAD" >&2
		return 1
	fi

	if [[ ! -s "$INPUT_PAYLOAD" ]]; then
		echo "validate_input_payload_json:: payload file is empty: $INPUT_PAYLOAD" >&2
		return 1
	fi

	if ! jq . "$INPUT_PAYLOAD" >/dev/null 2>&1; then
		local jq_error
		jq_error=$(jq . "$INPUT_PAYLOAD" 2>&1 | sed -n '1,3p')
		cat <<EOF >&2
validate_input_payload_json:: invalid JSON in payload file: ${INPUT_PAYLOAD}
validate_input_payload_json:: jq error: ${jq_error}
EOF
		return 1
	fi

	return 0
}

# Validate and resolve params.from_file path for payload loading
#
# Arguments:
#   $1 - raw_path: Value from params.from_file (may be relative or absolute)
#
# Outputs:
#   Writes resolved absolute path to stdout on success
#   Writes error messages to stderr on failure
#
# Returns:
#   0 if path is valid and resolves to a readable regular file
#   1 if path is invalid, empty, not found, is a directory, or unreadable
_resolve_from_file_path() {
	local raw_path="$1"
	local candidate
	local base

	local trailing
	trailing="${raw_path##*[![:space:]]}"
	raw_path="${raw_path%"$trailing"}"

	local leading
	leading="${raw_path%%[![:space:]]*}"
	raw_path="${raw_path#"$leading"}"
	if [[ -z "$raw_path" ]] || [[ "$raw_path" == "." ]] || [[ "$raw_path" == ".." ]]; then
		echo "parse_payload:: params.from_file is empty or invalid: ${raw_path:-empty}" >&2
		return 1
	fi

	if [[ "$raw_path" == /* ]]; then
		candidate="$raw_path"
	else
		for base in "${SEND_TO_SLACK_PAYLOAD_BASE_DIR:-}" "$PWD"; do
			[[ -z "$base" ]] || [[ ! -d "$base" ]] && continue
			candidate="${base}/${raw_path}"
			[[ -f "$candidate" ]] && [[ -r "$candidate" ]] && echo "$candidate" && return 0
			[[ -d "$candidate" ]] && echo "parse_payload:: params.from_file path is a directory: ${candidate}" >&2 && return 1
		done
		echo "parse_payload:: payload from file not found: ${raw_path}" >&2
		return 1
	fi

	[[ -f "$candidate" ]] && [[ -r "$candidate" ]] && echo "$candidate" && return 0
	[[ -d "$candidate" ]] && echo "parse_payload:: params.from_file path is a directory: ${candidate}" >&2 && return 1
	echo "parse_payload:: payload from file not found: ${raw_path}" >&2

	return 1
}
# Load params from params.raw when present
#
# Uses global variable: INPUT_PAYLOAD, modified in place
#
# Side Effects:
#   May replace .params with parsed JSON from params.raw
#
# Returns:
#   0 on success or when params.raw is absent
#   1 if raw string is not valid JSON
_load_raw_params() {
	local raw_params
	raw_params=$(jq -r '.params.raw // empty' "$INPUT_PAYLOAD")
	if [[ -z "$raw_params" ]]; then
		return 0
	fi

	echo "load_input_payload_params:: loading params from params.raw" >&2
	if ! echo "$raw_params" | jq . >/dev/null 2>&1; then
		echo "parse_payload:: raw payload is not valid JSON" >&2
		return 1
	fi

	local parsed_params
	parsed_params=$(echo "$raw_params" | jq '.')

	local parsed_params_file
	parsed_params_file=$(mktemp "$_SLACK_WORKSPACE/load_payload_params.raw.XXXXXX")
	echo "$parsed_params" >"$parsed_params_file"

	local updated_payload
	updated_payload=$(jq --slurpfile parsed_params "$parsed_params_file" '.params = $parsed_params[0]' "$INPUT_PAYLOAD")
	echo "$updated_payload" >"$INPUT_PAYLOAD"
	local param_keys
	param_keys=$(echo "$parsed_params" | jq -r 'keys | join(", ")')
	echo "load_input_payload_params:: loaded from params.raw, keys: ${param_keys}" >&2

	return 0
}

# Load params from params.from_file when present
#
# Uses global variable: INPUT_PAYLOAD, modified in place
#
# Side Effects:
#   May replace .params with JSON read from resolved file path
#
# Returns:
#   0 on success or when params.from_file is absent
#   1 if path invalid, file missing, or file contains invalid JSON
_load_from_file_params() {
	if ! jq -e '.params.from_file' "$INPUT_PAYLOAD" >/dev/null 2>&1; then
		return 0
	fi

	local source_file_path
	source_file_path=$(jq -r '.params.from_file' "$INPUT_PAYLOAD")
	source_file_path=$(_resolve_from_file_path "$source_file_path") || return 1
	echo "load_input_payload_params:: loading params from file: ${source_file_path}" >&2

	if ! jq . "$source_file_path" >/dev/null 2>&1; then
		echo "parse_payload:: payload file contains invalid JSON: $source_file_path" >&2
		return 1
	fi

	local file_params
	file_params=$(jq '.' "$source_file_path")

	local file_params_file
	file_params_file=$(mktemp "$_SLACK_WORKSPACE/load_payload_params.from_file.XXXXXX")
	echo "$file_params" >"$file_params_file"

	local updated_payload
	updated_payload=$(jq --slurpfile file_params "$file_params_file" '.params = $file_params[0]' "$INPUT_PAYLOAD")
	echo "$updated_payload" >"$INPUT_PAYLOAD"
	local param_keys
	param_keys=$(jq -r '.params | keys | join(", ")' "$INPUT_PAYLOAD")
	echo "load_input_payload_params:: loaded from params.from_file: ${source_file_path}, keys: ${param_keys}" >&2

	return 0
}

# Load input payload params conditionally, raw params or from_file
#
# Uses global variable: INPUT_PAYLOAD, modified in place
#
# Side Effects:
#   Modifies INPUT_PAYLOAD if raw params or from_file are specified
#
# Returns:
#   0 on success
#   1 if source file not found or invalid JSON
load_input_payload_params() {
	_load_raw_params || return 1
	_load_from_file_params || return 1

	return 0
}

# Resolve delivery method from payload token or webhook_url and environment
#
# Uses global variable: INPUT_PAYLOAD
#
# Side Effects:
#   May set SLACK_BOT_USER_OAUTH_TOKEN and WEBHOOK_URL from payload source keys
#   Sets DELIVERY_METHOD to api or webhook
#
# Returns:
#   0 on success
#   1 when neither token nor webhook_url is available after merge
_resolve_delivery_method() {
	local token_from_payload
	local webhook_from_payload
	token_from_payload=$(jq -r '.source.slack_bot_user_oauth_token // empty' "$INPUT_PAYLOAD")
	webhook_from_payload=$(jq -r '.source.webhook_url // empty' "$INPUT_PAYLOAD")

	if [[ -n "$token_from_payload" ]]; then
		SLACK_BOT_USER_OAUTH_TOKEN="$token_from_payload"
	fi

	if [[ -n "$webhook_from_payload" ]]; then
		WEBHOOK_URL="$webhook_from_payload"
	fi

	if [[ -n "${SLACK_BOT_USER_OAUTH_TOKEN:-}" ]]; then
		DELIVERY_METHOD="api"
	elif [[ -n "${WEBHOOK_URL:-}" ]]; then
		DELIVERY_METHOD="webhook"
	else
		echo "load_configuration:: either source.slack_bot_user_oauth_token or source.webhook_url is required" >&2
		return 1
	fi

	return 0
}

# Resolve CHANNEL from params and environment
#
# Uses global variable: INPUT_PAYLOAD
# Uses global variable: DELIVERY_METHOD, must be set first
#
# Side Effects:
#   Sets CHANNEL from params, with environment fallback when allowed
#
# Returns:
#   0 on success
#   1 when API delivery requires channel and none is set
_resolve_channel() {
	local source_exists="false"
	if jq -e '.source' "$INPUT_PAYLOAD" >/dev/null 2>&1; then
		source_exists="true"
	fi

	local env_channel_value="${CHANNEL:-}"
	CHANNEL=$(jq -r '.params.channel // empty' "$INPUT_PAYLOAD")
	if [[ "$DELIVERY_METHOD" == "api" ]]; then
		if [[ -z "$CHANNEL" ]]; then
			if [[ -n "$env_channel_value" ]]; then
				CHANNEL="$env_channel_value"
				echo "load_configuration:: params.channel not set, using CHANNEL from environment" >&2
			else
				if [[ "$source_exists" == "true" ]]; then
					echo "load_configuration:: params.channel is required for API delivery" >&2
				else
					echo "load_configuration:: params.channel is required and missing from payload and environment" >&2
				fi
				return 1
			fi
		fi
	else
		if [[ -z "$CHANNEL" ]] && [[ -n "$env_channel_value" ]]; then
			CHANNEL="$env_channel_value"
		fi
	fi

	return 0
}

# Reject bot identity params when not using API delivery
#
# Uses global variable: INPUT_PAYLOAD, DELIVERY_METHOD
#
# Returns:
#   0 when valid or identity params absent
#   1 when identity params are set with webhook delivery
_validate_bot_identity_params() {
	local bot_identity_username_param
	local bot_identity_icon_emoji_param
	local bot_identity_icon_url_param
	bot_identity_username_param=$(jq -r '.params.username // empty' "$INPUT_PAYLOAD")
	bot_identity_icon_emoji_param=$(jq -r '.params.icon_emoji // empty' "$INPUT_PAYLOAD")
	bot_identity_icon_url_param=$(jq -r '.params.icon_url // empty' "$INPUT_PAYLOAD")

	if [[ -n "$bot_identity_username_param" || -n "$bot_identity_icon_emoji_param" || -n "$bot_identity_icon_url_param" ]]; then
		if [[ "$DELIVERY_METHOD" != "api" ]]; then
			echo "load_configuration:: params.username, params.icon_emoji, and params.icon_url require API delivery with a bot token, not webhook" >&2
			return 1
		fi
	fi

	return 0
}

# Resolve EPHEMERAL_USER from params when using API delivery
#
# Uses global variable: INPUT_PAYLOAD, DELIVERY_METHOD
#
# Side Effects:
#   Unsets EPHEMERAL_USER when absent, exports when set with API delivery
#
# Returns:
#   0 on success
#   1 when ephemeral_user is set with webhook delivery
_resolve_ephemeral_user() {
	unset EPHEMERAL_USER 2>/dev/null || true
	local ephemeral_user_param
	ephemeral_user_param=$(jq -r '.params.ephemeral_user // empty' "$INPUT_PAYLOAD")
	if [[ -n "$ephemeral_user_param" ]]; then
		if [[ "$DELIVERY_METHOD" != "api" ]]; then
			echo "load_configuration:: params.ephemeral_user requires API delivery with a bot token, not webhook" >&2
			return 1
		fi
		EPHEMERAL_USER="$ephemeral_user_param"
		export EPHEMERAL_USER
	fi

	return 0
}

# Resolve DRY_RUN from params, environment, or default
#
# Uses global variable: INPUT_PAYLOAD
#
# Side Effects:
#   Sets DRY_RUN
#
# Returns:
#   0 always
_resolve_dry_run() {
	local params_dry_run
	params_dry_run=$(jq -r '.params.dry_run // empty' "$INPUT_PAYLOAD")
	if [[ -n "$params_dry_run" ]]; then
		DRY_RUN="$params_dry_run"
	elif [[ -z "${DRY_RUN:-}" ]]; then
		DRY_RUN="$DEFAULT_DRY_RUN"
	fi

	return 0
}

# Load configuration values from payload and environment variables
#
# Uses global variable: INPUT_PAYLOAD
#
# Side Effects:
#   Exports SLACK_BOT_USER_OAUTH_TOKEN, WEBHOOK_URL, CHANNEL, DRY_RUN, DELIVERY_METHOD
#   Sets and exports EPHEMERAL_USER when params.ephemeral_user is set, otherwise unsets EPHEMERAL_USER
#
# Returns:
#   0 on success
#   1 if required fields are missing
load_configuration() {
	if ! _resolve_delivery_method; then
		return 1
	fi

	if ! _resolve_channel; then
		return 1
	fi

	if ! _validate_bot_identity_params; then
		return 1
	fi

	if ! _resolve_ephemeral_user; then
		return 1
	fi

	_resolve_dry_run

	export DRY_RUN
	export SLACK_BOT_USER_OAUTH_TOKEN
	export CHANNEL
	export WEBHOOK_URL
	export DELIVERY_METHOD

	local token_preview
	local webhook_preview
	local ephemeral_preview
	token_preview="set"
	webhook_preview="set"
	ephemeral_preview="none"
	[[ -z "${SLACK_BOT_USER_OAUTH_TOKEN:-}" ]] && token_preview="empty"
	[[ -z "${WEBHOOK_URL:-}" ]] && webhook_preview="empty"
	[[ -n "${EPHEMERAL_USER:-}" ]] && ephemeral_preview="set"
	echo "load_configuration:: method=${DELIVERY_METHOD} channel=${CHANNEL:-none} dry_run=${DRY_RUN} token=${token_preview} webhook=${webhook_preview} ephemeral=${ephemeral_preview}" >&2

	return 0
}

# Main function to parse payload and create Slack API payload
#
# Arguments:
#   $1 - payload_file: Path to payload file
#
# Outputs:
#   Writes complete Slack API payload JSON to stdout
#
# Side Effects:
#   Sets global INPUT_PAYLOAD variable
#   Exports SLACK_BOT_USER_OAUTH_TOKEN, CHANNEL, DRY_RUN
#
# Returns:
#   0 on success
#   1 if parsing fails
parse_payload() {
	local payload_file="$1"

	INPUT_PAYLOAD="$payload_file"
	export INPUT_PAYLOAD

	if ! validate_input_payload_json; then
		return 1
	fi

	# Log sanitized payload if params.debug is true
	# This is one of the few options that can be used take precedence over the .from_file and .raw options
	local debug_enabled
	debug_enabled=$(jq -r '.params.debug // false' "$INPUT_PAYLOAD")
	if [[ "$debug_enabled" == "true" ]]; then
		_log_sanitized_payload
	fi

	if ! load_input_payload_params; then
		return 1
	fi

	if ! load_configuration; then
		return 1
	fi

	if ! process_blocks; then
		return 1
	fi

	return 0
}

# Block assembly, Slack limits, legacy attachments, Block Kit via create_block
source "${SEND_TO_SLACK_ROOT}/lib/parse/blocks.sh"
