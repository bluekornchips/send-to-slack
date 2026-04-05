#!/usr/bin/env bash
#
# Concourse put-step metadata assembly for send-to-slack
#

########################################################
# Default values
########################################################
METADATA="[]"
MAX_PAYLOAD_SIZE=262144

# Get safe payload size threshold to avoid exec argument overflow
#
# Outputs:
#   Writes safe byte limit to stdout
#
# Returns:
#   0 always
_get_safe_payload_size() {
	local arg_max
	arg_max=$(getconf ARG_MAX 2>/dev/null || echo "$MAX_PAYLOAD_SIZE")
	printf '%d' $((arg_max / 4))

	return 0
}

# Create Concourse metadata output structure
#
# Arguments:
#   $1 - payload: JSON payload to include in metadata, optional, only if SHOW_PAYLOAD is true
#   $2 - message_ts: Slack message ts for chat.update workflows, optional
#   $3 - channel: Slack channel id from API response, optional
#
# Side Effects:
# - Sets global METADATA variable with Concourse metadata format
#
# Returns:
# - 0 on successful metadata creation
create_metadata() {
	local payload="$1"
	local message_ts="${2:-}"
	local channel="${3:-}"
	local payload_for_metadata
	local safe_size

	METADATA=$(
		jq -n \
			--arg ts "${message_ts}" \
			--arg ch "${channel}" \
			'[]
        + (if ($ts != "" and $ts != "null") then [{"name": "message_ts", "value": $ts}] else [] end)
        + (if ($ch != "" and $ch != "null") then [{"name": "channel", "value": $ch}] else [] end)'
	)

	if [[ "${SHOW_METADATA}" != "true" ]]; then
		return 0
	fi

	if ! METADATA=$(echo "$METADATA" | jq \
		--arg dry_run "$DRY_RUN" \
		--arg show_metadata "$SHOW_METADATA" \
		--arg show_payload "$SHOW_PAYLOAD" \
		'. + [
          { "name": "dry_run", "value": $dry_run },
          { "name": "show_metadata", "value": $show_metadata },
          { "name": "show_payload", "value": $show_payload }
        ]' 2>/dev/null); then
		echo "create_metadata:: failed to append debug metadata fields" >&2
		return 1
	fi

	if [[ "${SHOW_PAYLOAD}" == "true" ]] && [[ -n "${payload}" ]]; then
		payload_for_metadata="$payload"
		safe_size=$(_get_safe_payload_size)

		if [[ ${#payload_for_metadata} -gt "$safe_size" ]]; then
			local stripped
			if stripped=$(echo "$payload_for_metadata" | jq 'del(.blocks, .attachments)' 2>/dev/null) &&
				[[ ${#stripped} -le "$safe_size" ]]; then
				if ! METADATA=$(echo "$METADATA" | jq \
					--arg payload "$stripped" \
					'. += [{"name": "payload", "value": $payload}, {"name": "payload_note", "value": "blocks and attachments excluded: payload exceeded safe metadata size"}]' \
					2>/dev/null); then
					echo "create_metadata:: failed to append stripped payload to metadata" >&2
					METADATA=$(echo "$METADATA" | jq '. += [{"name": "payload_skipped", "value": "payload too large for metadata"}]')
				fi
			else
				echo "create_metadata:: payload too large even after stripping blocks, skipping payload in metadata" >&2
				METADATA=$(echo "$METADATA" | jq '. += [{"name": "payload_skipped", "value": "payload too large for metadata"}]')
			fi
		else
			if ! METADATA=$(echo "$METADATA" | jq --arg payload "${payload_for_metadata}" '. += [{"name": "payload", "value": $payload}]' 2>/dev/null); then
				echo "create_metadata:: failed to append payload to metadata" >&2
				METADATA=$(echo "$METADATA" | jq '. += [{"name": "payload_skipped", "value": "metadata append failed"}]')
			fi
		fi
	fi

	return 0
}

# Emit Concourse resource JSON to stdout or SEND_TO_SLACK_OUTPUT
#
# Inputs:
# - $1 - timestamp: version.timestamp string
# - $2 - meta_ts: message ts for version.message_ts when non-empty
#
# Inputs from environment:
# - METADATA: JSON value for metadata field
# - SEND_TO_SLACK_OUTPUT: optional file path
#
# Returns:
# - 0 on success
# - 1 if jq fails
emit_concourse_output() {
	local timestamp="$1"
	local meta_ts="$2"
	local json_output

	if ! json_output=$(jq -n \
		--arg timestamp "${timestamp}" \
		--arg version_message_ts "${meta_ts}" \
		--argjson metadata "${METADATA}" \
		'{
      version: (
        if $version_message_ts != "" then { timestamp: $timestamp, message_ts: $version_message_ts }
        else { timestamp: $timestamp }
        end
      ),
      metadata: $metadata
    }'); then
		echo "emit_concourse_output:: failed to build output JSON" >&2
		return 1
	fi

	if [[ -n "${SEND_TO_SLACK_OUTPUT:-}" ]]; then
		jq -r '.' <<<"${json_output}" >"${SEND_TO_SLACK_OUTPUT}"
		echo "emit_concourse_output:: output written to ${SEND_TO_SLACK_OUTPUT}"

		return 0
	fi

	jq -r '.' <<<"${json_output}"

	return 0
}
