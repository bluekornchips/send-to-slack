#!/usr/bin/env bash
#
# Resolve Slack mentions and references to IDs
#
# Converts @user, #channel, or plain names/IDs to their Slack IDs.
# Supports: public channels, private channels, groups, direct messages, user IDs.
#
# API References:
#   https://docs.slack.dev/methods/users/users.list
#   https://docs.slack.dev/methods/conversations/conversations.list
#   https://docs.slack.dev/methods/conversations/conversations.open
#
set -eo pipefail

# Resolve a user mention or name to a user ID.
#
# Accepts user mentions (@john), names (john), or IDs (U123456).
# Returns the user ID or fails if user cannot be resolved.
#
# Arguments:
#   $1 - user_ref: user mention, name, or ID
#
# Output:
#   user ID to stdout on success
#
# Returns:
#   0 on successful resolution
#   1 on validation or API error
resolve_user_id() {
	local user_ref="$1"

	if [[ -z "$user_ref" ]]; then
		echo "resolve_user_id:: user_ref is required" >&2
		return 1
	fi

	if [[ -z "${SLACK_BOT_USER_OAUTH_TOKEN}" ]]; then
		echo "resolve_user_id:: SLACK_BOT_USER_OAUTH_TOKEN environment variable is required" >&2
		return 1
	fi

	# Remove @ prefix if present
	local user_name="${user_ref#@}"

	# If user already looks like a valid ID, return it
	if [[ "$user_name" =~ ^U[A-Z0-9]{8,}$ ]]; then
		echo "resolve_user_id:: already valid ID: ${user_name}" >&2
		echo "${user_name}"
		return 0
	fi

	echo "resolve_user_id:: resolving @${user_name}" >&2

	# Look up user by name via users.list API with pagination
	local cursor=""
	while true; do
		echo "resolve_user_id:: fetching users.list page (cursor=${cursor:-initial})" >&2

		local api_response
		if ! api_response=$(curl -s -X GET \
			-H "Authorization: Bearer ${SLACK_BOT_USER_OAUTH_TOKEN}" \
			--max-time 30 \
			--connect-timeout 10 \
			"https://slack.com/api/users.list?limit=100&cursor=${cursor}" 2>&1); then
			echo "resolve_user_id:: curl failed to send request" >&2
			return 1
		fi

		if [[ -z "$api_response" ]]; then
			echo "resolve_user_id:: empty response from Slack API" >&2
			return 1
		fi

		if ! jq -e . >/dev/null 2>&1 <<<"$api_response"; then
			echo "resolve_user_id:: invalid JSON response from Slack API" >&2
			return 1
		fi

		local ok
		ok=$(jq -r '.ok // false' <<<"$api_response")
		if [[ "$ok" != "true" ]]; then
			local error
			error=$(jq -r '.error // "unknown error"' <<<"$api_response")
			echo "resolve_user_id:: Slack API error: $error" >&2
			return 1
		fi

		# Search for matching user in this batch
		local found_id
		found_id=$(jq -r \
			--arg name "$user_name" \
			'.members[] | select(.name == $name) | .id' <<<"$api_response" | sed -n '1p')

		if [[ -n "$found_id" ]]; then
			echo "resolve_user_id:: found ${found_id} for @${user_name}" >&2
			echo "${found_id}"
			return 0
		fi

		# Check for more pages
		cursor=$(jq -r '.response_metadata.next_cursor // ""' <<<"$api_response")
		if [[ -z "$cursor" ]]; then
			echo "resolve_user_id:: user not found: $user_name" >&2
			return 1
		fi
	done
}

# Resolve a channel or group mention/name to a conversation ID.
#
# Accepts channel mentions (#general), names (general), group mentions (#private-group),
# or conversation IDs (C123456, G123456, Z123456).
# Returns the conversation ID or fails if not found.
#
# Arguments:
#   $1 - channel_ref: channel mention, name, or conversation ID
#
# Output:
#   conversation ID to stdout on success
#
# Returns:
#   0 on successful resolution
#   1 on validation or API error
resolve_channel_id() {
	local channel_ref="$1"

	if [[ -z "$channel_ref" ]]; then
		echo "resolve_channel_id:: channel_ref is required" >&2
		return 1
	fi

	if [[ -z "${SLACK_BOT_USER_OAUTH_TOKEN}" ]]; then
		echo "resolve_channel_id:: SLACK_BOT_USER_OAUTH_TOKEN environment variable is required" >&2
		return 1
	fi

	# Remove # prefix if present
	local channel_name="${channel_ref#\#}"

	# If already a valid conversation ID, return it
	# Supports: C (public), G (private/groups), D (direct), Z (shared)
	# Ref: https://docs.slack.dev/reference/conversations-api#channel_id
	if [[ "$channel_name" =~ ^[CGDZ][A-Z0-9]{8,}$ ]]; then
		echo "resolve_channel_id:: already valid ID: ${channel_name}" >&2
		echo "${channel_name}"
		return 0
	fi

	echo "resolve_channel_id:: resolving #${channel_name}" >&2

	# Look up channel/group by name via conversations.list API
	local cursor=""
	while true; do
		echo "resolve_channel_id:: fetching conversations.list page (cursor=${cursor:-initial})" >&2

		local api_response
		if ! api_response=$(curl -s -X GET \
			-H "Authorization: Bearer ${SLACK_BOT_USER_OAUTH_TOKEN}" \
			--max-time 30 \
			--connect-timeout 10 \
			"https://slack.com/api/conversations.list?limit=100&types=public_channel,private_channel&cursor=${cursor}" 2>&1); then
			echo "resolve_channel_id:: curl failed to send request" >&2
			return 1
		fi

		if [[ -z "$api_response" ]]; then
			echo "resolve_channel_id:: empty response from Slack API" >&2
			return 1
		fi

		if ! jq -e . >/dev/null 2>&1 <<<"$api_response"; then
			echo "resolve_channel_id:: invalid JSON response from Slack API" >&2
			return 1
		fi

		local ok
		ok=$(jq -r '.ok // false' <<<"$api_response")
		if [[ "$ok" != "true" ]]; then
			local error
			error=$(jq -r '.error // "unknown error"' <<<"$api_response")
			echo "resolve_channel_id:: Slack API error: $error" >&2
			return 1
		fi

		# Search for matching channel/group in this batch using jq --arg
		local found_id
		found_id=$(jq -r \
			--arg name "$channel_name" \
			'.channels[] | select(.name == $name) | .id' <<<"$api_response" | sed -n '1p')

		if [[ -n "$found_id" ]]; then
			echo "resolve_channel_id:: found ${found_id} for #${channel_name}" >&2
			echo "${found_id}"
			return 0
		fi

		# Check for more pages
		cursor=$(jq -r '.response_metadata.next_cursor // ""' <<<"$api_response")
		if [[ -z "$cursor" ]]; then
			echo "resolve_channel_id:: channel or group not found: $channel_name" >&2
			return 1
		fi
	done
}

# Resolve a direct message mention/name/ID to a DM conversation ID.
#
# Accepts user mentions (@john), names (john), user IDs (U123456),
# or DM conversation IDs (D123456). Returns the DM ID or fails if not found.
#
# Arguments:
#   $1 - dm_ref: user mention, name, ID, or DM conversation ID
#
# Output:
#   DM conversation ID to stdout on success
#
# Returns:
#   0 on successful resolution
#   1 on validation or API error
resolve_dm_id() {
	local dm_ref="$1"

	if [[ -z "$dm_ref" ]]; then
		echo "resolve_dm_id:: dm_ref is required" >&2
		return 1
	fi

	if [[ -z "${SLACK_BOT_USER_OAUTH_TOKEN}" ]]; then
		echo "resolve_dm_id:: SLACK_BOT_USER_OAUTH_TOKEN environment variable is required" >&2
		return 1
	fi

	# If already a valid DM ID, return it as-is
	if [[ "$dm_ref" =~ ^D[A-Z0-9]{8,}$ ]]; then
		echo "resolve_dm_id:: already valid DM ID: ${dm_ref}" >&2
		echo "$dm_ref"
		return 0
	fi

	echo "resolve_dm_id:: resolving DM for ${dm_ref}" >&2

	# Resolve user name/mention to user ID first
	local user_id
	if ! user_id=$(resolve_user_id "$dm_ref" 2>&1); then
		echo "resolve_dm_id:: could not resolve user: $dm_ref" >&2
		return 1
	fi

	echo "resolve_dm_id:: opening DM conversation via API (user_id=${user_id})" >&2

	# Open or get DM with the resolved user
	local api_response
	if ! api_response=$(curl -s -X POST \
		-H "Authorization: Bearer ${SLACK_BOT_USER_OAUTH_TOKEN}" \
		-H "Content-Type: application/x-www-form-urlencoded" \
		--data-urlencode "users=$user_id" \
		--max-time 30 \
		--connect-timeout 10 \
		"https://slack.com/api/conversations.open" 2>&1); then
		echo "resolve_dm_id:: curl failed to send request" >&2
		return 1
	fi

	if [[ -z "$api_response" ]]; then
		echo "resolve_dm_id:: empty response from Slack API" >&2
		return 1
	fi

	if ! jq -e . >/dev/null 2>&1 <<<"$api_response"; then
		echo "resolve_dm_id:: invalid JSON response from Slack API" >&2
		return 1
	fi

	local ok
	ok=$(jq -r '.ok // false' <<<"$api_response")
	if [[ "$ok" != "true" ]]; then
		local error
		error=$(jq -r '.error // "unknown error"' <<<"$api_response")
		echo "resolve_dm_id:: Slack API error: $error" >&2
		return 1
	fi

	# Extract and return the DM channel ID
	local dm_id
	dm_id=$(jq -r '.channel.id' <<<"$api_response")

	if [[ -z "$dm_id" || "$dm_id" == "null" ]]; then
		echo "resolve_dm_id:: could not extract DM channel ID from response" >&2
		return 1
	fi

	echo "resolve_dm_id:: found ${dm_id} for ${dm_ref}" >&2

	echo "$dm_id"
	return 0
}
