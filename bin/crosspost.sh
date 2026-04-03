#!/usr/bin/env bash
#
# Crosspost notification handler
# Sends a message to additional channels using the same params as a regular message.
# Depends on: send_notification from lib/slack-api.sh, parse_payload, _SLACK_WORKSPACE, NOTIFICATION_PERMALINK
#

# Send crosspost notifications to additional channels
#
# Crosspost accepts the same params as a regular message.
# The "channel" field works exactly like params.channel, it accepts string or array.
# $NOTIFICATION_PERMALINK is available for use in blocks via envsubst.
#
# Arguments:
#   $1 - input_payload: Path to the original input payload file
#
# Returns:
#   0 on success or if no crosspost configured
#   1 on failure
crosspost_notification() {
	local input_payload="$1"

	local crosspost
	crosspost=$(jq '.params.crosspost // {}' "$input_payload")

	if [[ -z "${crosspost}" ]] || [[ "${crosspost}" == "{}" ]]; then
		echo "crosspost_notification:: crosspost is empty, skipping."
		return 0
	fi

	# Extract channel(s) and normalize to array format.
	# Supports both crosspost.channel and crosspost.channels for compatibility.
	local channels_json
	channels_json=$(jq '.params.crosspost.channels // .params.crosspost.channel // null' "$input_payload")
	if [[ "$channels_json" == "null" ]] || [[ -z "$channels_json" ]]; then
		echo "crosspost_notification:: channel not set, skipping."
		return 0
	fi
	channels_json=$(echo "${channels_json}" | jq 'if type == "string" then [.] elif type == "array" then . else [] end')

	if [[ "${channels_json}" == "[]" ]]; then
		echo "crosspost_notification:: channel is empty, skipping."
		return 0
	fi

	# Get source from original payload to be used in crosspost
	local source_json
	source_json=$(jq '.source // {}' "$input_payload")

	# Check if no_link is set to skip automatic permalink
	local no_link
	no_link=$(jq -r '.params.crosspost.no_link // false' "$input_payload")

	# Get all crosspost params except channel selectors and no_link.
	local crosspost_params
	crosspost_params=$(jq '.params.crosspost | del(.channel, .channels, .no_link)' "$input_payload")

	# Save the original permalink before the loop, as send_notification overwrites NOTIFICATION_PERMALINK
	local original_permalink="$NOTIFICATION_PERMALINK"

	# By default, append a permalink block unless no_link is true
	if [[ "$no_link" != "true" ]] && [[ "${DELIVERY_METHOD:-api}" != "webhook" ]]; then
		# Add a context block with the permalink at the end of blocks
		# shellcheck disable=SC2016
		local permalink_block='{"context": {"elements": [{"type": "mrkdwn", "text": "<$NOTIFICATION_PERMALINK|View original message>"}]}}'
		crosspost_params=$(echo "$crosspost_params" | jq --argjson link "$permalink_block" '.blocks = (.blocks // []) + [$link]')
	elif [[ "$no_link" != "true" ]] && [[ "${DELIVERY_METHOD:-api}" == "webhook" ]]; then
		echo "crosspost_notification:: webhook delivery does not support permalink, skipping automatic link block" >&2
	fi

	# Process each channel
	local channel_count
	channel_count=$(jq '. | length' <<<"${channels_json}")
	echo "crosspost_notification:: sending to ${channel_count} channel(s)"

	for ((i = 0; i < channel_count; i++)); do
		local channel
		channel=$(jq -r ".[$i]" <<<"${channels_json}")
		echo "crosspost_notification:: processing channel ${channel}"

		# Restore original permalink before each iteration, as send_notification overwrites it
		NOTIFICATION_PERMALINK="$original_permalink"
		export NOTIFICATION_PERMALINK

		# Build full payload: source + crosspost params with channel replaced
		local crosspost_payload
		local crosspost_source_file
		local crosspost_params_file
		crosspost_source_file=$(mktemp "$_SLACK_WORKSPACE/crosspost.source.XXXXXX")
		crosspost_params_file=$(mktemp "$_SLACK_WORKSPACE/crosspost.params.XXXXXX")
		echo "$source_json" >"$crosspost_source_file"
		echo "$crosspost_params" >"$crosspost_params_file"

		crosspost_payload=$(jq -n \
			--slurpfile source "$crosspost_source_file" \
			--slurpfile params "$crosspost_params_file" \
			--arg channel "$channel" \
			'{
				"source": $source[0],
				"params": ($params[0] + {"channel": $channel})
			}')

		# Write payload to temp file for parsing
		local temp_payload
		temp_payload=$(mktemp "$_SLACK_WORKSPACE/send-to-slack.crosspost-payload.XXXXXX")
		if ! chmod 0600 "${temp_payload}"; then
			echo "crosspost_notification:: failed to secure temp payload ${temp_payload}" >&2
			rm -f "${temp_payload}"
			return 1
		fi
		echo "$crosspost_payload" >"$temp_payload"

		echo "crosspost_notification:: parsing crosspost payload for channel ${channel}" >&2

		# Parse the payload using the same parser as regular messages
		local parsed_payload
		if ! parsed_payload=$(parse_payload "$temp_payload"); then
			echo "crosspost_notification:: failed to parse payload for channel $channel" >&2
			rm -f "${temp_payload}"
			continue
		fi

		echo "crosspost_notification:: sending notification to channel ${channel}" >&2

		if ! send_notification "$parsed_payload"; then
			echo "crosspost_notification:: failed to send notification to channel $channel" >&2
			rm -f "${temp_payload}"
			continue
		fi

		local block_count
		block_count=$(echo "$parsed_payload" | jq '.blocks | length // 0')
		echo "crosspost_notification:: sent to channel ${channel} (blocks=${block_count})" >&2
		echo "crosspost_notification:: crosspost payload (sanitized):" >&2
		echo "$parsed_payload" | jq '{channel, blocks: [.blocks[]? | {type: .type}]}' 2>/dev/null >&2

		echo "crosspost_notification:: sent to channel ${channel}"
		rm -f "${temp_payload}"
	done

	return 0
}
