#!/usr/bin/env bash
#
# Exponential backoff retry helper
# Loaded by lib/slack/api.sh
# Depends on: RETRY_* from lib/slack/api/config.sh
#

# Retry a command with exponential backoff
#
# Exit code 2 from the command is treated as a permanent failure and is not
# retried.
#
# Arguments:
# $1 - max_attempts: Maximum number of retry attempts, default:
# RETRY_MAX_ATTEMPTS
#   $@ - command and arguments to execute, no eval
#
# Returns:
#   0 on success
#   2 on permanent failure (command returned 2)
#   otherwise last non-zero exit code after all retries
retry_with_backoff() {
	local max_attempts="${1:-$RETRY_MAX_ATTEMPTS}"
	shift

	if [[ -z "$max_attempts" ]]; then
		max_attempts="$RETRY_MAX_ATTEMPTS"
	fi

	if [[ $# -eq 0 ]]; then
		echo "retry_with_backoff:: command to execute is required" >&2
		return 1
	fi

	local attempt=1
	local delay="$RETRY_INITIAL_DELAY"
	local last_exit_code=1

	while [[ "$attempt" -le "$max_attempts" ]]; do
		echo "retry_with_backoff:: executing command (attempt" \
			"${attempt}/${max_attempts})" >&2

		local cmd_status=0
		"$@" || cmd_status=$?

		if [[ "$cmd_status" -eq 0 ]]; then
			return 0
		fi

		if [[ "$cmd_status" -eq 2 ]]; then
			return 2
		fi

		last_exit_code=$cmd_status

		if [[ "$attempt" -lt "$max_attempts" ]]; then
			echo "retry_with_backoff:: Attempt $attempt failed, retrying in" \
				"${delay}s." >&2
			sleep "$delay"

			delay=$((delay * RETRY_BACKOFF_MULTIPLIER))
			if [[ "$delay" -gt "$RETRY_MAX_DELAY" ]]; then
				delay="$RETRY_MAX_DELAY"
			fi

			attempt=$((attempt + 1))
		else
			echo "retry_with_backoff:: All $max_attempts attempts failed" >&2
			return $last_exit_code
		fi
	done

	return $last_exit_code
}
