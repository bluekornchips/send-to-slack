#!/usr/bin/env bash
#
# Dependency and Slack API connectivity checks for send-to-slack CLI
# Source this file from send-to-slack.sh, do not execute directly
#

# Verify jq is available on PATH
#
# Side Effects:
# - Writes one status line to stdout or stderr
#
# Returns:
# - 0 if jq is found
# - 1 if jq is missing
_health_check_require_jq() {
	if ! command -v jq >/dev/null 2>&1; then
		echo "health_check:: jq not found in PATH" >&2

		return 1
	fi

	echo "health_check:: jq found: $(command -v jq)"

	return 0
}

# Verify curl is available on PATH
#
# Side Effects:
# - Writes one status line to stdout or stderr
#
# Returns:
# - 0 if curl is found
# - 1 if curl is missing
_health_check_require_curl() {
	if ! command -v curl >/dev/null 2>&1; then
		echo "health_check:: curl not found in PATH" >&2

		return 1
	fi

	echo "health_check:: curl found: $(command -v curl)"

	return 0
}

# Optionally call Slack auth.test when a bot token is set
#
# Reads environment:
# - SLACK_BOT_USER_OAUTH_TOKEN, DRY_RUN, SKIP_SLACK_API_CHECK
#
# Side Effects:
# - Writes status lines to stdout and stderr
# - One short-lived temp file during the live API request path
#
# Returns:
# - 0 when no additional health error should be counted
# - 1 when the caller should increment its error counter
_health_check_slack_api() {
	if [[ -z "${SLACK_BOT_USER_OAUTH_TOKEN}" ]]; then
		echo "health_check:: SLACK_BOT_USER_OAUTH_TOKEN not set, skipping API connectivity check"

		return 0
	fi

	echo "health_check:: Testing Slack API connectivity."

	if [[ "${DRY_RUN}" == "true" || "${SKIP_SLACK_API_CHECK}" == "true" ]]; then
		echo "health_check:: Slack API connectivity check skipped (DRY_RUN or SKIP_SLACK_API_CHECK set)"

		return 0
	fi

	local body_file
	local http_code
	local response
	local team
	local user
	local error

	body_file=$(mktemp "${TMPDIR:-/tmp}/send-to-slack-health.XXXXXX")

	if [[ -z "${body_file}" || ! -f "${body_file}" ]]; then
		echo "health_check:: mktemp failed for Slack API check" >&2

		return 1
	fi

	chmod 0600 "${body_file}"

	http_code=$(curl -s -o "${body_file}" -w "%{http_code}" -X POST \
		-H "Authorization: Bearer ${SLACK_BOT_USER_OAUTH_TOKEN}" \
		--max-time 5 \
		--connect-timeout 5 \
		"https://slack.com/api/auth.test" 2>/dev/null)
	response=$(cat "${body_file}")
	rm -f "${body_file}"

	if [[ "${http_code}" == "200" ]]; then
		if echo "${response}" | jq -e '.ok == true' >/dev/null 2>&1; then
			team=$(echo "${response}" | jq -r '.team // "unknown"' 2>/dev/null)
			user=$(echo "${response}" | jq -r '.user // "unknown"' 2>/dev/null)
			echo "health_check:: Slack API accessible - Team: ${team}, User: ${user}"

			return 0
		fi

		error=$(echo "${response}" | jq -r '.error // "unknown"' 2>/dev/null)
		echo "health_check:: Slack API authentication failed: ${error}" >&2

		if [[ "${error}" != "invalid_auth" ]]; then

			return 1
		fi

		return 0
	fi

	echo "health_check:: Slack API not accessible (HTTP ${http_code})" >&2

	return 1
}

########################################################
# Core
########################################################

# Validate jq, curl, and optionally Slack auth.test
#
# Inputs:
# - No positional arguments, reads SLACK_BOT_USER_OAUTH_TOKEN, DRY_RUN,
#   SKIP_SLACK_API_CHECK from the environment when set
#
# Outputs:
# - Human-readable status lines on stdout for successful steps
# - Human-readable failure lines on stderr when a check fails
#
# Side Effects:
# - Writes status lines to stdout and stderr
#
# Returns:
# - 0 if all checks pass
# - 1 if any check fails
health_check() {
	local errors=0

	echo "health_check:: Starting health check."

	if ! _health_check_require_jq; then
		errors=$((errors + 1))
	fi

	if ! _health_check_require_curl; then
		errors=$((errors + 1))
	fi

	if ! _health_check_slack_api; then
		errors=$((errors + 1))
	fi

	if [[ "${errors}" -eq 0 ]]; then
		echo "health_check:: Health check passed"

		return 0
	fi

	echo "health_check:: Health check failed with ${errors} error(s)" >&2

	return 1
}
