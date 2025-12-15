#!/usr/bin/env bash
#
# Concourse resource 'out' script implementation
# Processes JSON payload from stdin and sends message to Slack
# Ref: https://concourse-ci.org/implementing-resource-types.html#resource-out
#
set -eo pipefail
set +x
umask 077

# Redirect stdout to stderr for logging, required for Concourse to capture output.
exec 3>&1
exec 1>&2

# Main entry point for Concourse resource 'out' operation
#
# Arguments:
#   $1 - destination: Directory where artifacts from previous steps are available
#       This is provided by Concourse and contains task outputs from previous steps
#
# Inputs:
# - Reads JSON payload from stdin with Slack configuration and message
#
# Side Effects:
# - Changes to destination directory so relative file paths resolve correctly
# - Calls send-to-slack.sh script to send message
# - Outputs version and metadata JSON to stdout
#
# Returns:
# - 0 on successful message delivery
# - 1 if file operations fail or send-to-slack.sh execution fails
main() {
	local destination="${1:-}"
	local input_file

	# Create temporary files
	SEND_TO_SLACK_OUTPUT=$(mktemp /tmp/resource-out.XXXXXX)
	if ! chmod 700 "$SEND_TO_SLACK_OUTPUT"; then
		echo "out:: failed to secure output file ${SEND_TO_SLACK_OUTPUT}" >&2
		rm -f "${SEND_TO_SLACK_OUTPUT}"
		return 1
	fi
	trap 'rm -f "${SEND_TO_SLACK_OUTPUT}"' EXIT ERR RETURN
	input_file=$(mktemp /tmp/resource-in.XXXXXX)
	if ! chmod 700 "$input_file"; then
		echo "out:: failed to secure input file ${input_file}" >&2
		rm -f "${input_file}"
		return 1
	fi
	trap 'rm -f "${input_file}"' EXIT ERR RETURN

	# Read the contents of stdin into the input file
	cat >"${input_file}"

	# Change to destination directory if provided (where task outputs are available)
	# This allows relative file paths in file blocks to resolve correctly
	# Ref: https://concourse-ci.org/tasks.html#schema.task-config.outputs
	if [[ -n "$destination" && -d "$destination" ]]; then
		cd "$destination" || {
			echo "out:: warning: could not change to destination directory: $destination" >&2
		}
	fi

	# Set SEND_TO_SLACK_OUTPUT so send-to-slack.sh writes JSON to this file
	export SEND_TO_SLACK_OUTPUT

	local send_to_slack_script="${SEND_TO_SLACK_SCRIPT:-/opt/resource/send-to-slack}"

	# Validate that send-to-slack.sh script exists
	if [[ ! -f "${send_to_slack_script}" ]]; then
		echo "out:: send-to-slack script not found at ${send_to_slack_script}" >&2
		return 1
	fi

	if ! "${send_to_slack_script}" <"${input_file}"; then
		echo "out:: failed to send notification to Slack" >&2
		return 1
	fi

	if [[ ! -f "${SEND_TO_SLACK_OUTPUT}" ]]; then
		echo "out:: output file not created by send-to-slack script" >&2
		return 1
	fi

	cat "${SEND_TO_SLACK_OUTPUT}" >&3

	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
