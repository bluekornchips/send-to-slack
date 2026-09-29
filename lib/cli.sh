#!/usr/bin/env bash
# shellcheck source=lib/get-version.sh
#
# CLI usage and argument parsing for send-to-slack
# Source this file from send-to-slack.sh, do not execute directly
# Depends on: print_version from lib/get-version.sh
#

usage() {
	cat <<EOF
Usage: send-to-slack [OPTIONS]

Send messages to Slack using Block Kit formatting.

OPTIONS:
  -f, -file, --file <path>  Read payload from file instead of stdin
  -v, --version             Display version information and exit
  -h, --help                Display this help message and exit
--health-check Validate dependencies and Slack API connectivity without sending

For more information, see: https://github.com/bluekornchips/send-to-slack
EOF
	return 0
}

# Parse command line arguments
#
# Arguments:
#   $1 - root_dir: repository or install root
#   $@ - remaining command line arguments
#
# Side Effects:
#   Sets health_check_mode and SEND_TO_SLACK_CLI_INPUT_FILE
#
# Returns:
#   0 on success
#   1 on parse error
#   2 if version or help was requested
parse_main_args() {
	local root_dir="$1"
	shift

	health_check_mode=false
	SEND_TO_SLACK_CLI_INPUT_FILE=""

	while [[ $# -gt 0 ]]; do
		case "$1" in
			-v | --version)
				if [[ -z "$root_dir" ]]; then
					echo "parse_main_args:: root directory is required for --version" >&2
					return 1
				fi
				# shellcheck source=lib/get-version.sh
				print_version "$root_dir"
				return 2
				;;
			-h | --help)
				usage
				return 2
				;;
			--health-check)
				health_check_mode=true
				shift
				;;
			-f | -file | --file)
				if [[ -n "${SEND_TO_SLACK_CLI_INPUT_FILE}" ]]; then
					echo "parse_main_args:: -f|-file|--file option can only be specified" \
						"once" >&2
					return 1
				fi
				if [[ $# -lt 2 ]]; then
					echo "parse_main_args:: -f|-file|--file requires a file path argument" >&2
					return 1
				fi
				SEND_TO_SLACK_CLI_INPUT_FILE="$2"
				shift 2
				;;
			*)
				echo "parse_main_args:: unknown option: ${1}" >&2
				echo "parse_main_args:: use -h for usage" >&2
				return 1
				;;
		esac
	done

	export SEND_TO_SLACK_CLI_INPUT_FILE

	return 0
}
