#!/usr/bin/env bash
#
# Concourse resource 'check' script implementation
# For notification resources, we don't track versions
# Returns empty array to indicate no versions available
# Ref: https://concourse-ci.org/implementing-resource-types.html#resource-check
#
set -eo pipefail
umask 077

# Redirect stdout to stderr for logging, required for Concourse to capture output.
exec 3>&1
exec 1>&2

# Main entry point for Concourse resource 'check' operation
#
# Inputs:
# - Reads JSON payload from stdin with source configuration
#
# Side Effects:
# - Validates JSON input
# - Outputs empty version array to stdout. These notification resources don't track versions.
#
# Returns:
# - 0 on successful validation
# - 1 if JSON payload is invalid
main() {
	local payload
	payload=$(mktemp /tmp/resource-in.XXXXXX)
	if ! chmod 0600 "$payload"; then
		echo "check:: failed to secure temp payload ${payload}" >&2
		rm -f "${payload}"
		return 1
	fi
	trap 'rm -f "${payload}"' EXIT ERR RETURN

	cat >"${payload}" <&0

	if ! jq . "${payload}" >/dev/null 2>&1; then
		echo "check:: invalid JSON input in payload" >&2
		return 1
	fi

	echo "[]" >&3

	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
