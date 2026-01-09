#!/usr/bin/env bash
#
# Concourse resource 'check' script implementation
# For notification resources, we emit the packaged VERSION so downstream succeeds
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
# - Outputs a single version array with the resource VERSION to stdout
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

	local script_dir
	script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

	local version_path
	version_path="${VERSION_PATH:-${script_dir}/../VERSION}"

	local version_value="${VERSION_VALUE:-}"
	if [[ -z "$version_value" && -f "$version_path" ]]; then
		version_value=$(tr -d '\r\n' <"$version_path")
	fi

	if [[ -z "$version_value" ]]; then
		version_value=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || {
			echo "check:: failed to generate version fallback timestamp" >&2
			return 1
		}
	fi

	jq -n --arg version "$version_value" '[{"version": $version}]' >&3

	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
