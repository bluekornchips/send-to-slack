#!/usr/bin/env bats
#
# Test file for in.sh
#
GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
SCRIPT="$GIT_ROOT/concourse/resource-type/scripts/in.sh"
[[ ! -f "$SCRIPT" ]] && echo "Script not found: $SCRIPT" >&2 && return 1

setup() {
	test_timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
	TEST_PAYLOAD_FILE=$(mktemp /tmp/in_payload.XXXXXX)

	export test_timestamp
	export TEST_PAYLOAD_FILE

	return 0
}

teardown() {
	[[ -f "${TEST_PAYLOAD_FILE:-}" ]] && rm -f "${TEST_PAYLOAD_FILE}"
	return 0
}

########################################################
# Helpers
########################################################
# Create version input for testing
# Optional argument: timestamp (defaults to test_timestamp from setup)
#shellcheck disable=SC2120
create_version_input() {
	local timestamp="${1:-${test_timestamp}}"
	jq -n --arg timestamp "${timestamp}" '{"version": {"timestamp": $timestamp}}' >"${TEST_PAYLOAD_FILE}"
}

create_empty_version_input() {
	jq -n '{"version": {}}' >"${TEST_PAYLOAD_FILE}"
}

########################################################
# main
########################################################
@test "main:: successfully fetches resource with timestamp" {
	create_version_input

	run "$SCRIPT" <"${TEST_PAYLOAD_FILE}"

	[[ "$status" -eq 0 ]]

	local version_timestamp
	version_timestamp=$(jq -r '.version.timestamp' <<<"${output}")
	[[ "${version_timestamp}" == "${test_timestamp}" ]]
}

@test "main:: outputs correct JSON format with version" {
	create_version_input

	run "$SCRIPT" <"${TEST_PAYLOAD_FILE}"

	[[ "$status" -eq 0 ]]

	echo "${output}" | grep -q "version"
	echo "${output}" | grep -q "timestamp"
}

@test "main:: defaults to none when version.timestamp is missing" {
	create_empty_version_input

	run "$SCRIPT" <"${TEST_PAYLOAD_FILE}"

	[[ "$status" -eq 0 ]]

	local version_timestamp
	version_timestamp=$(jq -r '.version.timestamp' <<<"${output}")
	[[ "${version_timestamp}" == "none" ]]
}
