#!/usr/bin/env bash
#
# Dependency and Slack API connectivity checks for send-to-slack CLI
# Source this file from send-to-slack.sh, do not execute directly
#

# Validate jq, curl, and optionally Slack auth.test
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

	if ! command -v jq >/dev/null 2>&1; then
		echo "health_check:: jq not found in PATH" >&2
		errors=$((errors + 1))
	else
		echo "health_check:: jq found: $(command -v jq)"
	fi

	if ! command -v curl >/dev/null 2>&1; then
		echo "health_check:: curl not found in PATH" >&2
		errors=$((errors + 1))
	else
		echo "health_check:: curl found: $(command -v curl)"
	fi

	if [[ -n "${SLACK_BOT_USER_OAUTH_TOKEN}" ]]; then
		echo "health_check:: Testing Slack API connectivity."
		if [[ "${DRY_RUN}" == "true" || "${SKIP_SLACK_API_CHECK}" == "true" ]]; then
			echo "health_check:: Slack API connectivity check skipped (DRY_RUN or SKIP_SLACK_API_CHECK set)"
		else
			local response
			local http_code
			http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
				-H "Authorization: Bearer ${SLACK_BOT_USER_OAUTH_TOKEN}" \
				--max-time 5 \
				--connect-timeout 5 \
				"https://slack.com/api/auth.test" 2>/dev/null)

			if [[ "$http_code" == "200" ]]; then
				response=$(curl -s -X POST \
					-H "Authorization: Bearer ${SLACK_BOT_USER_OAUTH_TOKEN}" \
					--max-time 5 \
					--connect-timeout 5 \
					"https://slack.com/api/auth.test" 2>/dev/null)

				if echo "$response" | jq -e '.ok == true' >/dev/null 2>&1; then
					local team
					local user
					team=$(echo "$response" | jq -r '.team // "unknown"' 2>/dev/null)
					user=$(echo "$response" | jq -r '.user // "unknown"' 2>/dev/null)
					echo "health_check:: Slack API accessible - Team: $team, User: $user"
				else
					local error
					error=$(echo "$response" | jq -r '.error // "unknown"' 2>/dev/null)
					echo "health_check:: Slack API authentication failed: $error" >&2
					if [[ "$error" != "invalid_auth" ]]; then
						errors=$((errors + 1))
					fi
				fi
			else
				echo "health_check:: Slack API not accessible (HTTP $http_code)" >&2
				errors=$((errors + 1))
			fi
		fi
	else
		echo "health_check:: SLACK_BOT_USER_OAUTH_TOKEN not set, skipping API connectivity check"
	fi

	if [[ "$errors" -eq 0 ]]; then
		echo "health_check:: Health check passed"
		return 0
	fi

	echo "health_check:: Health check failed with $errors error(s)" >&2

	return 1
}
