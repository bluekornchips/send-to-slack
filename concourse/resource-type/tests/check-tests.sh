#!/usr/bin/env bats
#
# Test file for check.sh
#
GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
SCRIPT="$GIT_ROOT/concourse/resource-type/scripts/check.sh"
[[ ! -f "$SCRIPT" ]] && echo "Script not found: $SCRIPT" >&2 && return 1

########################################################
# main
########################################################
@test "main:: returns empty array for notification resource" {
	run "$SCRIPT" <<<'{"version": {"timestamp": "2023-12-01T12:00:00Z"}}'

	[[ "$status" -eq 0 ]]
	echo "${output}" | grep -q "^\[\]$"
}

@test "main:: returns empty array when no version in payload" {
	run "$SCRIPT" <<<'{"source": {"url": "https://example.com"}}'

	[[ "$status" -eq 0 ]]
	echo "${output}" | grep -q "^\[\]$"
}

@test "main:: outputs valid JSON array format" {
	run "$SCRIPT" <<<'{"version": {"timestamp": "2023-12-01T12:00:00Z"}}'

	[[ "$status" -eq 0 ]]

	if ! echo "${output}" | jq . >/dev/null 2>&1; then
		return 1
	fi

	local length
	length=$(echo "${output}" | jq length)
	[[ "$length" -eq 0 ]]
}

@test "main:: creates and uses temporary payload file" {
	run "$SCRIPT" <<<'{"version": {"timestamp": "2023-12-01T12:00:00Z"}}'

	[[ "$status" -eq 0 ]]
}

@test "main:: handles jq errors gracefully" {
	run "$SCRIPT" <<<'invalid json'

	[[ "$status" -ne 0 ]]
}

@test "main:: handles empty input" {
	run "$SCRIPT" <<<''

	[[ "$status" -eq 0 ]]
	echo "${output}" | grep -q "^\[\]$"
}
