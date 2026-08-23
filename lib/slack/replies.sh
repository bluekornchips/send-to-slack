#!/usr/bin/env bash
#
# Thread replies handler, source this file from send-to-slack.sh, do not execute
# directly.
# Sends each entry in thread_replies as a separate message in a thread.
# Depends on: send_notification from lib/slack/api.sh, parse_payload,
# _build_derived_input_payload, _SLACK_WORKSPACE
#

# Send each entry in thread_replies as a separate thread message
#
# Inputs:
# - $1 input_payload_file: path to original input payload file, used to read
# source credentials
# - $2 thread_ts: the thread timestamp to reply to
# - $3 parsed_payload: the parsed payload JSON string, used to read
# thread_replies and channel
#
# Side Effects:
# - Calls send_notification for each reply entry
# - Writes diagnostic and warning lines to stderr, success lines to stderr
#
# Returns:
# - 0 when replies are skipped, or when all iterations finish, including
# per-reply parse or send warnings
# - 1 when jq is missing, parsed payload or input file cannot be read, or
# workspace is invalid
send_thread_replies() {
	local input_payload_file="$1"
	local thread_ts="$2"
	local parsed_payload="$3"

	if [[ -z "$thread_ts" || "$thread_ts" == "null" ]]; then
		echo "send_thread_replies:: thread_ts is not set, skipping replies" >&2
		return 0
	fi

	local thread_replies
	if ! thread_replies=$(echo "$parsed_payload" \
		| jq '.thread_replies // empty'); then
		return 1
	fi

	if [[ -z "$thread_replies" || "$thread_replies" == "null" ||
		"$thread_replies" == "[]" ]]; then
		return 0
	fi

	local reply_count
	if ! reply_count=$(echo "$thread_replies" | jq 'length'); then
		echo "send_thread_replies:: failed to count thread_replies" >&2
		return 1
	fi

	if ((reply_count == 0)); then
		return 0
	fi

	if [[ -z "$input_payload_file" ]] || [[ ! -f "$input_payload_file" ]] \
		|| [[ ! -r "$input_payload_file" ]]; then
		return 1
	fi

	if [[ -z "$_SLACK_WORKSPACE" ]] || [[ ! -d "$_SLACK_WORKSPACE" ]]; then
		return 1
	fi

	local channel
	if ! channel=$(echo "$parsed_payload" | jq -r '.channel'); then
		echo "send_thread_replies:: failed to read channel from parsed payload" >&2
		return 1
	fi

	local source_json
	if ! source_json=$(jq '.source // {}' "$input_payload_file"); then
		echo "send_thread_replies:: failed to read source from input payload file" >&2
		return 1
	fi

	for ((i = 0; i < reply_count; i++)); do
		local reply_blocks
		if ! reply_blocks=$(echo "$thread_replies" | jq ".[$i].blocks"); then
			continue
		fi

		local reply_params
		if ! reply_params=$(jq -n \
			--argjson blocks "$reply_blocks" \
			--slurpfile parent "$input_payload_file" \
			--arg channel "$channel" \
			--arg thread_ts "$thread_ts" \
			'
			($parent[0].params // {}) as $pp
			| {
				"channel": $channel,
				"thread_ts": $thread_ts,
				"blocks": $blocks
			}
 | if (($pp.username | type) == "string") and (($pp.username | length) > 0) then
				. + {username: $pp.username}
				else .
			end
 | if (($pp.icon_emoji | type) == "string") \
				and (($pp.icon_emoji | length) > 0) then
				. + {icon_emoji: $pp.icon_emoji}
				else .
			end
 | if (($pp.icon_url | type) == "string") and (($pp.icon_url | length) > 0) then
				. + {icon_url: $pp.icon_url}
				else .
			end
			'); then
			continue
		fi

		local reply_payload_file
		if ! reply_payload_file=$(_build_derived_input_payload "$source_json" \
			"$reply_params" "thread-reply"); then
			continue
		fi

		echo "send_thread_replies:: parsing reply $((i + 1)) of ${reply_count}" >&2

		local reply_parsed
		if ! reply_parsed=$(parse_payload "$reply_payload_file"); then
			rm -f "${reply_payload_file}"
			continue
		fi

		if ! send_notification "$reply_parsed"; then
			rm -f "${reply_payload_file}"
			continue
		fi

		echo "send_thread_replies:: reply $((i + 1)) of ${reply_count} sent" >&2
		rm -f "${reply_payload_file}"
	done

	return 0
}
