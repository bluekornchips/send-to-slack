#!/usr/bin/env bash
#
# Thread replies handler
# Sends each entry in thread_replies as a separate message in a thread.
# Depends on: send_notification from lib/slack-api.sh, parse_payload, _SLACK_WORKSPACE
#

# Send each entry in thread_replies as a separate thread message
#
# Inputs:
# - $1 input_payload_file: path to original input payload file, used to read source credentials
# - $2 thread_ts: the thread timestamp to reply to
# - $3 parsed_payload: the parsed payload JSON string, used to read thread_replies and channel
#
# Side Effects:
# - Calls send_notification for each reply entry
# - Outputs warnings to stderr for failed replies, does not fail overall
#
# Returns:
# - 0 always
send_thread_replies() {
	local input_payload_file="$1"
	local thread_ts="$2"
	local parsed_payload="$3"

	if [[ -z "$thread_ts" || "$thread_ts" == "null" ]]; then
		echo "send_thread_replies:: thread_ts is not set, skipping replies" >&2
		return 0
	fi

	local thread_replies
	thread_replies=$(echo "$parsed_payload" | jq '.thread_replies // empty')
	if [[ -z "$thread_replies" || "$thread_replies" == "null" || "$thread_replies" == "[]" ]]; then
		return 0
	fi

	local reply_count
	reply_count=$(echo "$thread_replies" | jq 'length')
	if ((reply_count == 0)); then
		return 0
	fi

	local channel
	channel=$(echo "$parsed_payload" | jq -r '.channel')

	local source_json
	source_json=$(jq '.source // {}' "$input_payload_file")

	echo "send_thread_replies:: sending ${reply_count} thread reply(s) with thread_ts: ${thread_ts}"

	for ((i = 0; i < reply_count; i++)); do
		local reply_blocks
		reply_blocks=$(echo "$thread_replies" | jq ".[$i].blocks")

		local reply_payload_file
		reply_payload_file=$(mktemp "$_SLACK_WORKSPACE/thread-reply.payload.XXXXXX")
		if ! chmod 0600 "${reply_payload_file}"; then
			echo "send_thread_replies:: warning: failed to secure temp file for reply $((i + 1)), skipping" >&2
			rm -f "${reply_payload_file}"
			continue
		fi

		local reply_source_file
		local reply_blocks_file
		reply_source_file=$(mktemp "$_SLACK_WORKSPACE/thread-reply.source.XXXXXX")
		reply_blocks_file=$(mktemp "$_SLACK_WORKSPACE/thread-reply.blocks.XXXXXX")
		echo "$source_json" >"$reply_source_file"
		echo "$reply_blocks" >"$reply_blocks_file"

		jq -n \
			--slurpfile source "$reply_source_file" \
			--slurpfile blocks "$reply_blocks_file" \
			--arg channel "$channel" \
			--arg thread_ts "$thread_ts" \
			'{
				"source": $source[0],
				"params": {
					"channel": $channel,
					"thread_ts": $thread_ts,
					"blocks": $blocks[0]
				}
			}' >"$reply_payload_file"

		rm -f "$reply_source_file" "$reply_blocks_file"

		echo "send_thread_replies:: parsing reply $((i + 1)) of ${reply_count}" >&2

		local reply_parsed
		if ! reply_parsed=$(parse_payload "$reply_payload_file"); then
			echo "send_thread_replies:: warning: reply $((i + 1)) failed to parse, continuing" >&2
			rm -f "${reply_payload_file}"
			continue
		fi

		if ! send_notification "$reply_parsed"; then
			echo "send_thread_replies:: warning: reply $((i + 1)) failed to send, continuing" >&2
			rm -f "${reply_payload_file}"
			continue
		fi

		echo "send_thread_replies:: reply $((i + 1)) of ${reply_count} sent"
		rm -f "${reply_payload_file}"
	done

	return 0
}
