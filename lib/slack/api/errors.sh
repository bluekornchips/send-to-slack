#!/usr/bin/env bash
#
# Slack API error reporting and classification helpers
# Loaded by lib/slack/api.sh
# Depends on: DOC_URL_* from lib/slack/api/config.sh
#

# Check if error code is in the given list. Used for retry vs fail branching.
#
# Inputs:
# - $1 - code: error code string to look up
# - $2 ... - list of error code strings
#
# Returns:
# - 0 if code is in the list, 1 otherwise
_is_error_in_list() {
	local code="$1"
	shift
	local elem
	for elem in "$@"; do
		if [[ "$code" == "$elem" ]]; then
			return 0
		fi
	done

	return 1
}

# Handle Slack API errors with detailed context
#
# Arguments:
#   $1 - response: Slack API response JSON
#   $2 - context: Additional context string
#
# Side Effects:
# - Outputs detailed error messages to stderr
#
# Returns:
# - 0 always
handle_slack_api_error() {
	local response="$1"
	local context="$2"

	local error_code
	error_code=$(echo "$response" | jq -r '.error // "unknown"' 2>/dev/null)

	case "$error_code" in
	"rate_limited")
		echo "handle_slack_api_error:: Rate limited. Slack API is throttling" \
			"requests." >&2
		echo "handle_slack_api_error:: Consider implementing retry logic or" \
			"reducing request frequency." >&2
		echo "handle_slack_api_error:: See: $DOC_URL_RATE_LIMITS" >&2
		;;
	"invalid_auth")
		echo "handle_slack_api_error:: Authentication failed. Check your" \
			"SLACK_BOT_USER_OAUTH_TOKEN." >&2
		echo "handle_slack_api_error:: Token may be expired or invalid." >&2
		echo "handle_slack_api_error:: See: $DOC_URL_AUTHENTICATION" >&2
		;;
	"channel_not_found")
		echo "handle_slack_api_error:: Channel not found. Verify the channel" \
			"name/ID exists and the bot has access." >&2
		echo "handle_slack_api_error:: See: $DOC_URL_CONVERSATIONS_LIST" >&2
		;;
	"not_in_channel")
		echo "handle_slack_api_error:: Bot is not in the specified channel. Invite" \
			"the bot to the channel first." >&2
		echo "handle_slack_api_error:: See: $DOC_URL_CONVERSATIONS_JOIN" >&2
		;;
	"missing_scope")
		echo "handle_slack_api_error:: Missing required OAuth scope. Check your" \
			"bot's scopes in Slack app settings." >&2
		local needed_scope
		needed_scope=$(echo "$response" | jq -r '.needed // "unknown"' 2>/dev/null)
		if [[ -n "$needed_scope" ]] && [[ "$needed_scope" != "unknown" ]]; then
			echo "handle_slack_api_error:: Required scope: $needed_scope" >&2
			echo "handle_slack_api_error:: See: $DOC_URL_SCOPES" >&2
		fi
		;;
	"invalid_blocks")
		echo "handle_slack_api_error:: Invalid blocks in payload. Check block" \
			"structure and validation rules." >&2
		echo "handle_slack_api_error:: See: $DOC_URL_BLOCK_KIT_BLOCKS" >&2
		echo "handle_slack_api_error:: Use Block Kit Builder to validate:" \
			"https://app.slack.com/block-kit-builder" >&2
		;;
	"invalid_attachments")
		echo "handle_slack_api_error:: Invalid attachments in payload. Common" \
			"issues:" >&2
		echo "handle_slack_api_error:: - Attachment structure must match Slack's" \
			"format" >&2
		echo "handle_slack_api_error:: - Maximum 20 attachments per message" >&2
		echo "handle_slack_api_error:: See: $DOC_URL_LEGACY_ATTACHMENTS" >&2
		;;
	*)
		echo "handle_slack_api_error:: Slack API error: $error_code" >&2
		echo "handle_slack_api_error:: See: $DOC_URL_CHAT_POSTMESSAGE_ERRORS" >&2
		;;
	esac

	if [[ -n "$context" ]]; then
		echo "handle_slack_api_error:: Context: $context" >&2
	fi

	if [[ -n "$response" ]]; then
		echo "handle_slack_api_error:: Full Slack API response:" >&2
		echo "$response" | jq . >&2 2>/dev/null || echo "$response" >&2
	fi

	return 0
}
