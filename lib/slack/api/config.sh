#!/usr/bin/env bash
#
# Slack Web API constants and documentation URLs
# Loaded by lib/slack/api.sh
#

########################################################
# API endpoints and retry policy
########################################################
SLACK_API_URL="https://slack.com/api"
CHAT_POST_MESSAGE="chat.postMessage"
CHAT_POST_EPHEMERAL="chat.postEphemeral"
CHAT_UPDATE="chat.update"
CHAT_GET_PERMALINK="chat.getPermalink"

RETRY_MAX_ATTEMPTS=3
RETRY_INITIAL_DELAY=1
RETRY_MAX_DELAY=60
RETRY_BACKOFF_MULTIPLIER=2

ERROR_CODES_TRUE_FAILURES=(
	"invalid_auth"
	"channel_not_found"
	"not_in_channel"
	"user_not_in_channel"
	"missing_scope"
	"invalid_blocks"
	"invalid_attachments"
	"message_not_found"
	"cant_update_message")

########################################################
# Documentation URLs
########################################################
DOC_URL_AUTHENTICATION="https://api.slack.com/authentication"
DOC_URL_BLOCK_KIT_BLOCKS="https://docs.slack.dev/reference/block-kit/blocks"
DOC_URL_CHAT_POSTMESSAGE_ERRORS="https://api.slack.com/methods/chat.postMessage#errors"
DOC_URL_CONVERSATIONS_JOIN="https://api.slack.com/methods/conversations.join"
DOC_URL_CONVERSATIONS_LIST="https://api.slack.com/methods/conversations.list"
DOC_URL_LEGACY_ATTACHMENTS="https://api.slack.com/reference/messaging/payload#legacy"
DOC_URL_RATE_LIMITS="https://api.slack.com/docs/rate-limits"
DOC_URL_SCOPES="https://api.slack.com/scopes"
