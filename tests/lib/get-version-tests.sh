#!/usr/bin/env bats
#
# Tests for lib/get-version.sh
#

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		fail "Failed to get git root"
	fi

	LIB="$GIT_ROOT/lib/get-version.sh"
	if [[ ! -f "$LIB" ]]; then
		fail "Script not found: $LIB"
	fi

	export GIT_ROOT
	export LIB

	return 0
}

setup() {
	source "$LIB"

	return 0
}

@test "get_version:: reads VERSION file and strips newlines" {
	local fixture_root
	fixture_root=$(mktemp -d "${BATS_TEST_TMPDIR}/get-version-fixture.XXXXXX")
	printf '1.2.3\n' >"${fixture_root}/VERSION"

	run get_version "$fixture_root"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "1.2.3" ]]

	rm -rf "$fixture_root"
}

@test "get_version:: strips carriage return from VERSION" {
	local fixture_root
	fixture_root=$(mktemp -d "${BATS_TEST_TMPDIR}/get-version-crlf.XXXXXX")
	printf 'v9.0.0\r\n' >"${fixture_root}/VERSION"

	run get_version "$fixture_root"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "v9.0.0" ]]

	rm -rf "$fixture_root"
}

@test "get_version:: fails when root path is empty" {
	run get_version ""
	[[ "$status" -eq 1 ]]
	[[ -z "$output" ]]
}

@test "get_version:: fails when VERSION is missing" {
	local fixture_root
	fixture_root=$(mktemp -d "${BATS_TEST_TMPDIR}/get-version-nover.XXXXXX")

	run get_version "$fixture_root"
	[[ "$status" -eq 1 ]]
	[[ -z "$output" ]]

	rm -rf "$fixture_root"
}

@test "get_version:: fails when VERSION is empty" {
	local fixture_root
	fixture_root=$(mktemp -d "${BATS_TEST_TMPDIR}/get-version-empty.XXXXXX")
	: >"${fixture_root}/VERSION"

	run get_version "$fixture_root"
	[[ "$status" -eq 1 ]]
	[[ -z "$output" ]]

	rm -rf "$fixture_root"
}

@test "get_commit:: returns short hash from a linked worktree" {
	if ! command -v "git" >/dev/null 2>&1; then
		skip "git not available"
	fi

	local worktree_dir
	local expected_commit

	worktree_dir=$(mktemp -d "${BATS_TEST_TMPDIR}/get-commit-worktree.XXXXXX")
	git -C "$GIT_ROOT" worktree add "$worktree_dir" HEAD
	expected_commit=$(git -C "$worktree_dir" rev-parse --short HEAD)

	run get_commit "$worktree_dir"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "$expected_commit" ]]

	git -C "$GIT_ROOT" worktree remove --force "$worktree_dir"
}

@test "get_commit:: fails for a non-git directory" {
	local fixture_root
	fixture_root=$(mktemp -d "${BATS_TEST_TMPDIR}/get-commit-plain.XXXXXX")

	run get_commit "$fixture_root"
	[[ "$status" -eq 1 ]]

	rm -rf "$fixture_root"
}
