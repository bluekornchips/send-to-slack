#!/usr/bin/env bash
#
# Slack Web API and Incoming Webhook delivery helpers.
# Used by send-to-slack.sh, crosspost.sh, and replies.sh.
#
# Implementation lives in lib/slack/api/; this file loads those modules.
#

SLACK_API_MODULES=(
	"config"
	"errors"
	"retry"
	"http"
	"permalink"
	"send"
	"update"
)

if [[ -z "${SEND_TO_SLACK_ROOT:-}" ]]; then
	SEND_TO_SLACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
	export SEND_TO_SLACK_ROOT
fi

api_dir="${SEND_TO_SLACK_ROOT}/lib/slack/api"
for module in "${SLACK_API_MODULES[@]}"; do
	if ! source_required "${api_dir}/${module}.sh"; then
		return 1
	fi
done
