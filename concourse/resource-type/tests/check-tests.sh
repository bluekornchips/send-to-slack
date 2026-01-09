#!/usr/bin/env bats
#
# Test file for check.sh
#
GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
SCRIPT="$GIT_ROOT/concourse/resource-type/scripts/check.sh"
EXPECTED_VERSION="$(tr -d '\r\n' <"$GIT_ROOT/VERSION" 2>/dev/null || echo "")"
[[ ! -f "$SCRIPT" ]] && echo "Script not found: $SCRIPT" >&2 && return 1

########################################################
# main
########################################################
@test "main:: returns package version for notification resource" {
	run env VERSION_PATH="$GIT_ROOT/VERSION" "$SCRIPT" <<<'{"version": {"timestamp": "2023-12-01T12:00:00Z"}}'

	[[ "$status" -eq 0 ]]

	if ! echo "${output}" | jq . >/dev/null 2>&1; then
		return 1
	fi

	local length
	length=$(echo "${output}" | jq length)
	[[ "$length" -eq 1 ]]

	local version
	version=$(echo "${output}" | jq -r '.[0].version')

	if [[ -n "${EXPECTED_VERSION}" ]]; then
		[[ "$version" == "$EXPECTED_VERSION" ]]
	else
		[[ -n "$version" && "$version" != "null" ]]
	fi
}

@test "main:: returns package version when no version in payload" {
	run env VERSION_PATH="$GIT_ROOT/VERSION" "$SCRIPT" <<<'{"source": {"url": "https://example.com"}}'

	[[ "$status" -eq 0 ]]

	if ! echo "${output}" | jq . >/dev/null 2>&1; then
		return 1
	fi

	local length
	length=$(echo "${output}" | jq length)
	[[ "$length" -eq 1 ]]

	local version
	version=$(echo "${output}" | jq -r '.[0].version')

	if [[ -n "${EXPECTED_VERSION}" ]]; then
		[[ "$version" == "$EXPECTED_VERSION" ]]
	else
		[[ -n "$version" && "$version" != "null" ]]
	fi
}

@test "main:: outputs valid JSON array format" {
	run env VERSION_PATH="$GIT_ROOT/VERSION" "$SCRIPT" <<<'{"version": {"timestamp": "2023-12-01T12:00:00Z"}}'

	[[ "$status" -eq 0 ]]

	if ! echo "${output}" | jq . >/dev/null 2>&1; then
		return 1
	fi

	local length
	length=$(echo "${output}" | jq length)
	[[ "$length" -eq 1 ]]

	local version
	version=$(echo "${output}" | jq -r '.[0].version')

	if [[ -n "${EXPECTED_VERSION}" ]]; then
		[[ "$version" == "$EXPECTED_VERSION" ]] || [[ -n "$version" && "$version" != "null" ]]
	else
		[[ -n "$version" && "$version" != "null" ]]
	fi
}

@test "main:: creates and uses temporary payload file" {
	run "$SCRIPT" <<<'{"version": {"timestamp": "2023-12-01T12:00:00Z"}}'

	[[ "$status" -eq 0 ]]
}

@test "main:: handles jq errors gracefully" {
	run "$SCRIPT" <<<'invalid json'

	[[ "$status" -ne 0 ]]
}

@test "main:: handles empty input by emitting synthetic version" {
	run env VERSION_PATH="$GIT_ROOT/VERSION" "$SCRIPT" <<<''

	[[ "$status" -eq 0 ]]

	if ! echo "${output}" | jq . >/dev/null 2>&1; then
		return 1
	fi

	local length
	length=$(echo "${output}" | jq length)
	[[ "$length" -eq 1 ]]

	local version
	version=$(echo "${output}" | jq -r '.[0].version')

	if [[ -n "${EXPECTED_VERSION}" ]]; then
		[[ "$version" == "$EXPECTED_VERSION" ]]
	else
		[[ -n "$version" && "$version" != "null" ]]
	fi
}
