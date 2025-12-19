#!/usr/bin/env bats
#
# Tests for ci/build.sh helper functions
#

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		fail "setup_file:: git root not found"
	fi

	BUILD_SCRIPT="${GIT_ROOT}/ci/build.sh"
	if [[ ! -f "$BUILD_SCRIPT" ]]; then
		fail "setup_file:: build script missing: $BUILD_SCRIPT"
	fi

	ORIGINAL_GIT_ROOT="$GIT_ROOT"

	export BUILD_SCRIPT
	export ORIGINAL_GIT_ROOT
}

setup() {
	OUTPUT_DIR="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/send-to-slack-build.XXXXXX")"
	GIT_ROOT="$ORIGINAL_GIT_ROOT"

	export OUTPUT_DIR
	export GIT_ROOT

	source "$BUILD_SCRIPT"
}

teardown() {
	if [[ -n "$OUTPUT_DIR" && -d "$OUTPUT_DIR" ]]; then
		rm -rf "$OUTPUT_DIR"
	fi

	GIT_ROOT="$ORIGINAL_GIT_ROOT"
}

@test "build.sh:: parse_args accepts all as dockerfile choice" {
	DOCKERFILE_CHOICE=""
	run parse_args --dockerfile all
	[[ "$status" -eq 0 ]]
	[[ "$DOCKERFILE_CHOICE" == "all" ]]
}

@test "build.sh:: parse_args accepts concourse as dockerfile choice" {
	DOCKERFILE_CHOICE=""
	run parse_args --dockerfile concourse
	[[ "$status" -eq 0 ]]
	[[ "$DOCKERFILE_CHOICE" == "concourse" ]]
}

@test "build.sh:: parse_args accepts test as dockerfile choice" {
	DOCKERFILE_CHOICE=""
	run parse_args --dockerfile test
	[[ "$status" -eq 0 ]]
	[[ "$DOCKERFILE_CHOICE" == "test" ]]
}

@test "build.sh:: parse_args accepts remote as dockerfile choice" {
	DOCKERFILE_CHOICE=""
	run parse_args --dockerfile remote
	[[ "$status" -eq 0 ]]
	[[ "$DOCKERFILE_CHOICE" == "remote" ]]
}

@test "build.sh:: parse_args accepts empty string as dockerfile choice" {
	DOCKERFILE_CHOICE=""
	run parse_args --dockerfile ""
	[[ "$status" -eq 0 ]]
	[[ "$DOCKERFILE_CHOICE" == "" ]]
}

@test "build.sh:: parse_args rejects invalid dockerfile choice" {
	DOCKERFILE_CHOICE=""
	run parse_args --dockerfile invalid
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "invalid dockerfile choice"
	echo "$output" | grep -q "allowed: concourse|test|remote|all"
}

@test "build.sh:: parse_args requires argument for --dockerfile" {
	DOCKERFILE_CHOICE=""
	run parse_args --dockerfile
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "option --dockerfile requires an argument"
}

@test "build.sh:: parse_args accepts --gha flag" {
	GITHUB_ACTION="false"
	run parse_args --gha
	[[ "$status" -eq 0 ]]
	[[ "$GITHUB_ACTION" == "true" ]]
}

@test "build.sh:: parse_args accepts --github-action flag" {
	GITHUB_ACTION="false"
	run parse_args --github-action
	[[ "$status" -eq 0 ]]
	[[ "$GITHUB_ACTION" == "true" ]]
}

@test "build.sh:: parse_args accepts --no-cache flag" {
	NO_CACHE="false"
	run parse_args --no-cache
	[[ "$status" -eq 0 ]]
	[[ "$NO_CACHE" == "true" ]]
}

@test "build.sh:: parse_args accepts --healthcheck flag" {
	SEND_HEALTHCHECK_QUERY="false"
	run parse_args --healthcheck
	[[ "$status" -eq 0 ]]
	[[ "$SEND_HEALTHCHECK_QUERY" == "true" ]]
}

@test "build.sh:: parse_args accepts --send-test-message flag" {
	SEND_TEST_MESSAGE="false"
	run parse_args --send-test-message
	[[ "$status" -eq 0 ]]
	[[ "$SEND_TEST_MESSAGE" == "true" ]]
}

@test "build.sh:: parse_args accepts --help flag" {
	run parse_args --help
	[[ "$status" -eq 2 ]]
}

@test "build.sh:: parse_args accepts -h flag" {
	run parse_args -h
	[[ "$status" -eq 2 ]]
}

@test "build.sh:: parse_args rejects unknown option" {
	run parse_args --unknown-option
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "unknown option"
}
