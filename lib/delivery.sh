#!/usr/bin/env bash
# shellcheck source=lib/slack/api/send.sh
# shellcheck source=lib/slack/api/update.sh
# shellcheck source=lib/slack/crosspost.sh
# shellcheck source=lib/slack/replies.sh
# shellcheck source=lib/slack/utils/resolve-mentions.sh
#
# Delivery orchestration for send-to-slack
# Source this file from send-to-slack.sh, do not execute directly
# Depends on: send_notification, update_message, send_thread_replies,
# crosspost_notification
#

# Extract a non-null string field from Slack API RESPONSE JSON
#
# Arguments:
#   $1 - field: jq field name (e.g. ts, channel)
#
# Outputs:
#   Field value on stdout, or empty if missing/null/invalid JSON
#
# Returns:
#   0 always
_response_field() {
	local field="$1"
	local value=""
	if [[ -n "${RESPONSE:-}" ]] && jq . >/dev/null 2>&1 <<<"$RESPONSE"; then
		value=$(jq -r --arg f "$field" '.[$f] // empty' <<<"$RESPONSE")
	fi
	[[ "$value" == "null" ]] && value=""
	printf '%s' "$value"
	return 0
}

# Resolve message_ts and run chat.update when params request an update
#
# Inputs:
# - $1 - input_payload: path to raw Concourse-style input JSON
# - $2 - parsed_payload: JSON string from parse_payload
#
# Side Effects:
# - May call update_message and set RESPONSE
#
# Returns:
# - 0 if chat.update completed successfully
# - 1 on validation or API failure
_run_chat_update_from_input() {
	local input_payload="$1"
	local parsed_payload="$2"
	local update_ts
	local message_ts_file

	update_ts=$(jq -r '.params.message_ts // empty' "${input_payload}")
	message_ts_file=$(jq -r '.params.message_ts_file // empty' "${input_payload}")

	if [[ -z "$update_ts" ]] && [[ -n "$message_ts_file" ]]; then
		if [[ ! -f "$message_ts_file" ]]; then
			echo "run_chat_update_from_input:: params.message_ts_file: file not found:" \
				"${message_ts_file}" >&2

			return 1
		fi
		update_ts=$(<"$message_ts_file")
	fi

	if [[ -z "$update_ts" ]]; then
		return 1
	fi

	echo "run_chat_update_from_input:: updating existing Slack message via" \
		"chat.update"
	local update_channel
	update_channel=$(jq -r '.params.channel // empty' "${input_payload}")

	if [[ -z "$update_channel" || "$update_channel" == "null" ]]; then
		echo "run_chat_update_from_input:: params.channel is required when" \
			"params.message_ts is set" >&2
		return 1
	fi

	if [[ "${DELIVERY_METHOD:-api}" != "api" ]]; then
		echo "run_chat_update_from_input:: params.message_ts requires API delivery," \
			"not webhook" >&2
		return 1
	fi

	local update_channel_resolved
	update_channel_resolved="$update_channel"
	if [[ "${DRY_RUN:-}" != "true" ]]; then
		# shellcheck source=lib/slack/utils/resolve-mentions.sh
		if ! update_channel_resolved=$(resolve_channel_id "$update_channel"); then
			echo "run_chat_update_from_input:: failed to resolve params.channel for" \
				"chat.update, channel ID is required" >&2
			return 1
		fi
	fi

	# shellcheck source=lib/slack/api/update.sh
	if ! update_message "$update_channel_resolved" "$update_ts" \
		"$parsed_payload"; then
		echo "run_chat_update_from_input:: failed to update Slack message" >&2
		return 1
	fi

	return 0
}

# Send notification, thread replies, and crosspost for a parsed payload
#
# Inputs:
# - $1 - input_payload: path to raw Concourse-style input JSON
# - $2 - parsed_payload: JSON string from parse_payload
#
# Side Effects:
# - Calls send_notification, send_thread_replies, crosspost_notification
# - Uses/sets RESPONSE and delivery globals
#
# Returns:
# - 0 on success
# - 1 on delivery failure
_run_send_from_input() {
	local input_payload="$1"
	local parsed_payload="$2"

	echo "delivery:: sending notification"
	# shellcheck source=lib/slack/api/send.sh
	if ! send_notification "$parsed_payload"; then
		echo "delivery:: failed to send notification" >&2
		return 1
	fi

	if [[ "${DELIVERY_METHOD:-api}" != "api" ]]; then
		# shellcheck source=lib/slack/replies.sh
		echo "delivery:: delivery method webhook does not support thread replies," \
			"skipping send_thread_replies" >&2
		# shellcheck source=lib/slack/crosspost.sh
		echo "delivery:: delivery method webhook does not support crosspost," \
			"skipping crosspost_notification" >&2
		return 0
	fi

	if [[ -n "${EPHEMERAL_USER:-}" ]]; then
		# shellcheck source=lib/slack/crosspost.sh
		echo "delivery:: chat.postEphemeral does not support thread replies or" \
			"crosspost, skipping send_thread_replies and crosspost_notification" >&2
		return 0
	fi

	local primary_ts
	primary_ts=$(_response_field "ts")

	local reply_thread_ts
	reply_thread_ts=$(jq -r '.thread_ts // empty' <<<"$parsed_payload")
	if [[ -z "$reply_thread_ts" || "$reply_thread_ts" == "null" ]]; then
		reply_thread_ts="${primary_ts:-}"
	fi

	# shellcheck source=lib/slack/replies.sh
	if ! send_thread_replies "${input_payload}" "$reply_thread_ts" \
		"$parsed_payload"; then
		echo "delivery:: send_thread_replies encountered failures, continuing" >&2
	fi

	# shellcheck source=lib/slack/crosspost.sh
	if ! crosspost_notification "${input_payload}"; then
		echo "delivery:: failed to crosspost notification" >&2
		return 1
	fi

	return 0
}

# Decide whether to update or send, then run the selected delivery path
#
# Inputs:
# - $1 - input_payload: path to raw Concourse-style input JSON
# - $2 - parsed_payload: JSON string from parse_payload
#
# Returns:
# - 0 on success
# - 1 on delivery failure
run_delivery_from_input() {
	local input_payload="$1"
	local parsed_payload="$2"
	local update_ts
	local message_ts_file

	update_ts=$(jq -r '.params.message_ts // empty' "${input_payload}")
	message_ts_file=$(jq -r '.params.message_ts_file // empty' "${input_payload}")

	if [[ -z "$update_ts" && -z "$message_ts_file" ]]; then
		_run_send_from_input "$input_payload" "$parsed_payload"
		return $?
	fi

	if _run_chat_update_from_input "$input_payload" "$parsed_payload"; then
		return 0
	fi

	return 1
}

# Backward-compatible alias for tests and callers
run_send_from_input() {
	_run_send_from_input "$@"
}
