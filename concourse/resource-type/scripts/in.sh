#!/usr/bin/env bash
#
# Concourse resource 'in' script implementation
# Reads version from stdin and outputs version JSON
# Ref: https://concourse-ci.org/implementing-resource-types.html#resource-in
#

# Redirect stdout to stderr for logging, required for Concourse to capture output.
exec 3>&1
exec 1>&2

# Main entry point for Concourse resource 'in' operation
#
# Inputs:
# - $1 dest, destination directory where resource files are written
# - Reads JSON payload from stdin with version information
#
# Side Effects:
# - Writes version JSON to <dest>/version when dest is provided
# - Outputs version JSON to stdout (fd3)
#
# Returns:
# - 0 on successful version extraction and output
# - 1 if JSON payload is invalid or version extraction fails
main() {
	local dest
	local payload
	local version
	local message_ts_value
	local version_json

	dest="${1:-}"

	payload=$(mktemp /tmp/resource-in.XXXXXX)
	if ! chmod 0600 "$payload"; then
		echo "in:: failed to secure temp payload ${payload}" >&2
		rm -f "${payload}"
		return 1
	fi
	trap 'rm -f "${payload}"' EXIT ERR RETURN

	cat >"${payload}" <&0

	# Validate JSON input before parsing
	if ! jq . "${payload}" >/dev/null 2>&1; then
		echo "in:: invalid JSON input in payload" >&2
		return 1
	fi

	# Use the version as the timestamp because we don't care about the source
	version=$(jq -r '.version.timestamp // "none"' "${payload}")
	message_ts_value=$(jq -r '.version.message_ts // empty' "${payload}")

	if [[ -n "$message_ts_value" ]] && [[ "$message_ts_value" != "null" ]]; then
		version_json=$(jq -n \
			--arg timestamp "${version}" \
			--arg message_ts "${message_ts_value}" \
			'{"version": {"timestamp": $timestamp, "message_ts": $message_ts}}')
	else
		version_json=$(jq -n --arg timestamp "${version}" '{"version": {"timestamp": $timestamp}}')
	fi

	echo "${version_json}" >&3

	if [[ -n "${dest}" ]]; then
		echo "${version_json}" >"${dest}/version"
	fi

	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	set -eo pipefail
	umask 077
	main "$@"
	exit $?
fi
