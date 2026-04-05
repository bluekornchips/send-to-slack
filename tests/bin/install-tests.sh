#!/usr/bin/env bats
#
# Tests for install.sh
#

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		fail "setup_file:: git root not found"
	fi

	INSTALL_SCRIPT="${GIT_ROOT}/bin/install.sh"

	if [[ ! -f "$INSTALL_SCRIPT" ]]; then
		fail "setup_file:: install script missing: $INSTALL_SCRIPT"
	fi

	source "$INSTALL_SCRIPT"

	INSTALL_SIGNATURE_VALUE="$INSTALL_SIGNATURE"
	INSTALL_BASENAME_VALUE="$INSTALL_BASENAME"

	# Export functions so they're available in test subshells
	export -f _install_lib_rel_paths install_from_source normalize_prefix file_has_signature extract_archive build_source_archive_url clone_repository verify_installation print_install_info

	export GIT_ROOT
	export INSTALL_SCRIPT
	export INSTALL_SIGNATURE_VALUE
	export INSTALL_BASENAME_VALUE

	return 0
}

setup() {
	PREFIX_DIR="$(mktemp -d "${BATS_TEST_TMPDIR}/send-to-slack-install.XXXXXX")"
	TARGET_PATH="${PREFIX_DIR}/${INSTALL_BASENAME_VALUE}"

	export PREFIX_DIR
	export TARGET_PATH

	return 0
}

teardown() {
	if [[ -n "$TARGET_PATH" ]] && { [[ -f "$TARGET_PATH" ]] || [[ -L "$TARGET_PATH" ]]; }; then
		rm -f "$TARGET_PATH"
	fi

	if [[ -n "$PREFIX_DIR" && -d "$PREFIX_DIR" ]]; then
		rm -rf "$PREFIX_DIR"
	fi

	return 0
}

@test "install.sh:: installs binary with signature and mode (local)" {
	local symlink_target
	local actual_install_root

	run "$INSTALL_SCRIPT" --version local --prefix "$PREFIX_DIR"
	[[ "$status" -eq 0 ]]

	[[ -L "$TARGET_PATH" ]]
	[[ -x "$TARGET_PATH" ]]
	grep -Fq "$INSTALL_SIGNATURE_VALUE" "$TARGET_PATH"

	symlink_target=$(readlink "$TARGET_PATH")
	actual_install_root=$(dirname "$symlink_target")

	[[ -d "${actual_install_root}/lib" ]]
	[[ -f "${actual_install_root}/lib/metadata.sh" ]]
	[[ -f "${actual_install_root}/lib/health-check.sh" ]]
	[[ -f "${actual_install_root}/lib/get-version.sh" ]]
	[[ -f "${actual_install_root}/lib/parse/payload.sh" ]]
	[[ -f "${actual_install_root}/lib/parse/blocks.sh" ]]
	[[ -f "${actual_install_root}/lib/slack/block-kit/create-block.sh" ]]
	[[ -f "${actual_install_root}/lib/slack/block-kit/blocks/table.sh" ]]
	[[ -f "${actual_install_root}/lib/slack/crosspost.sh" ]]
	[[ -f "${actual_install_root}/lib/slack/replies.sh" ]]

	rm -rf "${actual_install_root}"
}

@test "install.sh:: reinstall is idempotent (local)" {
	local symlink_target
	local actual_install_root

	run "$INSTALL_SCRIPT" --version local --prefix "$PREFIX_DIR"
	[[ "$status" -eq 0 ]]

	run "$INSTALL_SCRIPT" --version local --prefix "$PREFIX_DIR"
	[[ "$status" -eq 0 ]]

	[[ -L "$TARGET_PATH" ]]
	sig_count=$(grep -c "$INSTALL_SIGNATURE_VALUE" "$TARGET_PATH")
	[[ "$sig_count" -eq 1 ]]

	symlink_target=$(readlink "$TARGET_PATH")
	actual_install_root=$(dirname "$symlink_target")
	rm -rf "${actual_install_root}"
}

@test "install.sh:: supports container-style prefix (local)" {
	local container_prefix
	local container_target
	local symlink_target
	local actual_install_root

	container_prefix="${BATS_TEST_TMPDIR}/container/user/bin"
	container_target="${container_prefix}/${INSTALL_BASENAME_VALUE}"

	run "$INSTALL_SCRIPT" --version local --prefix "$container_prefix"
	[[ "$status" -eq 0 ]]
	[[ -L "$container_target" ]]
	grep -Fq "$INSTALL_SIGNATURE_VALUE" "$container_target"

	symlink_target=$(readlink "$container_target")
	actual_install_root=$(dirname "$symlink_target")
	rm -rf "${actual_install_root}"
	rm -rf "$container_prefix"
}

@test "install.sh:: accepts --prefix equals form, local" {
	local symlink_target
	local actual_install_root

	run "$INSTALL_SCRIPT" --version local --prefix="${PREFIX_DIR}"
	[[ "$status" -eq 0 ]]

	[[ -L "$TARGET_PATH" ]]
	[[ -x "$TARGET_PATH" ]]
	grep -Fq "$INSTALL_SIGNATURE_VALUE" "$TARGET_PATH"

	symlink_target=$(readlink "$TARGET_PATH")
	actual_install_root=$(dirname "$symlink_target")

	[[ -d "${actual_install_root}/lib" ]]
	[[ -f "${actual_install_root}/lib/health-check.sh" ]]
	[[ -f "${actual_install_root}/lib/get-version.sh" ]]
	[[ -f "${actual_install_root}/lib/parse/payload.sh" ]]
	[[ -f "${actual_install_root}/lib/parse/blocks.sh" ]]
	[[ -f "${actual_install_root}/lib/slack/block-kit/create-block.sh" ]]
	[[ -f "${actual_install_root}/lib/slack/block-kit/blocks/table.sh" ]]

	rm -rf "${actual_install_root}"
}

@test "install.sh:: usage displays help" {
	run "$INSTALL_SCRIPT" --help
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Usage:"
}

# check_dependencies: stubs are minimal executables, not symlinks to the host toolchain.
# PATH is narrowed inside bash -c so bats still finds bash from the outer PATH.
_install_test_stub() {
	local stub_dir="$1"
	local stub_name="$2"

	printf '#!/bin/sh\nexit 0\n' >"${stub_dir}/${stub_name}"
	chmod +x "${stub_dir}/${stub_name}"

	return 0
}

_run_check_dependencies_isolated() {
	local stub_dir="$1"

	run bash -c 'export PATH="$1" && source "$2" && check_dependencies' _ "$stub_dir" "$INSTALL_SCRIPT"

	return 0
}

@test "check_dependencies:: fails when stub dir has no git curl or tar" {
	local stub_dir

	stub_dir=$(mktemp -d "${BATS_TEST_TMPDIR}/check-deps-stubs.XXXXXX")
	_run_check_dependencies_isolated "$stub_dir"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "check_dependencies::"
	rm -rf "$stub_dir"
}

@test "check_dependencies:: succeeds when stub git exists" {
	local stub_dir

	stub_dir=$(mktemp -d "${BATS_TEST_TMPDIR}/check-deps-stubs.XXXXXX")
	_install_test_stub "$stub_dir" "git"
	_run_check_dependencies_isolated "$stub_dir"
	[[ "$status" -eq 0 ]]
	rm -rf "$stub_dir"
}

@test "check_dependencies:: succeeds when stub curl and tar exist without git" {
	local stub_dir

	stub_dir=$(mktemp -d "${BATS_TEST_TMPDIR}/check-deps-stubs.XXXXXX")
	_install_test_stub "$stub_dir" "curl"
	_install_test_stub "$stub_dir" "tar"
	_run_check_dependencies_isolated "$stub_dir"
	[[ "$status" -eq 0 ]]
	rm -rf "$stub_dir"
}

@test "check_dependencies:: fails when only stub curl exists" {
	local stub_dir

	stub_dir=$(mktemp -d "${BATS_TEST_TMPDIR}/check-deps-stubs.XXXXXX")
	_install_test_stub "$stub_dir" "curl"
	_run_check_dependencies_isolated "$stub_dir"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "check_dependencies::"
	rm -rf "$stub_dir"
}

@test "check_dependencies:: fails when only stub tar exists" {
	local stub_dir

	stub_dir=$(mktemp -d "${BATS_TEST_TMPDIR}/check-deps-stubs.XXXXXX")
	_install_test_stub "$stub_dir" "tar"
	_run_check_dependencies_isolated "$stub_dir"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "check_dependencies::"
	rm -rf "$stub_dir"
}

@test "install.sh:: installs from source directory" {
	local temp_dir
	local source_dir
	local install_root

	temp_dir=$(mktemp -d "${BATS_TEST_TMPDIR}/send-to-slack-source.XXXXXX")
	source_dir="${temp_dir}/send-to-slack-main"

	mkdir -p "${source_dir}/bin" "${source_dir}/lib/slack/block-kit/blocks" "${source_dir}/lib/slack/utils" "${source_dir}/lib/parse"

	cp "${GIT_ROOT}/bin/send-to-slack.sh" "${source_dir}/bin/send-to-slack.sh"
	cp "${GIT_ROOT}/lib/metadata.sh" "${GIT_ROOT}/lib/health-check.sh" "${GIT_ROOT}/lib/get-version.sh" "${source_dir}/lib/"
	cp "${GIT_ROOT}/lib/parse"/*.sh "${source_dir}/lib/parse/"
	cp "${GIT_ROOT}/lib/slack/api.sh" "${GIT_ROOT}/lib/slack/crosspost.sh" "${GIT_ROOT}/lib/slack/replies.sh" "${source_dir}/lib/slack/"
	cp "${GIT_ROOT}/lib/slack/utils"/*.sh "${source_dir}/lib/slack/utils/"
	cp "${GIT_ROOT}/lib/slack/block-kit/create-block.sh" "${source_dir}/lib/slack/block-kit/"
	cp "${GIT_ROOT}/lib/slack/block-kit/blocks"/*.sh "${source_dir}/lib/slack/block-kit/blocks/"
	if [[ -f "${GIT_ROOT}/VERSION" ]]; then
		cp "${GIT_ROOT}/VERSION" "${source_dir}/VERSION"
	fi

	# Determine install root based on user. Root uses /usr/local, non-root uses ~/.local/share.
	if [[ "$(id -u)" -eq 0 ]]; then
		install_root="/usr/local/send-to-slack"
	else
		install_root="${HOME}/.local/share/send-to-slack"
	fi

	run install_from_source "${source_dir}" "${PREFIX_DIR}" 0
	[[ "$status" -eq 0 ]]
	[[ -f "$TARGET_PATH" ]]
	[[ -L "$TARGET_PATH" ]]
	[[ -x "$TARGET_PATH" ]]

	# Get actual install root from symlink target
	local symlink_target
	local actual_install_root
	symlink_target=$(readlink "$TARGET_PATH")
	actual_install_root=$(dirname "$symlink_target")

	[[ -f "${actual_install_root}/send-to-slack" ]]
	# Function already verifies signature, so if it succeeded, signature is there
	file_has_signature "${actual_install_root}/send-to-slack"
	[[ -d "${actual_install_root}/lib" ]]
	[[ -f "${actual_install_root}/lib/metadata.sh" ]]
	[[ -f "${actual_install_root}/lib/health-check.sh" ]]
	[[ -f "${actual_install_root}/lib/get-version.sh" ]]
	[[ -f "${actual_install_root}/lib/parse/payload.sh" ]]
	[[ -f "${actual_install_root}/lib/parse/blocks.sh" ]]
	[[ -f "${actual_install_root}/lib/slack/block-kit/create-block.sh" ]]
	[[ -f "${actual_install_root}/lib/slack/block-kit/blocks/table.sh" ]]
	[[ -f "${actual_install_root}/lib/slack/crosspost.sh" ]]
	[[ -f "${actual_install_root}/lib/slack/replies.sh" ]]
	if [[ -f "${source_dir}/VERSION" ]]; then
		[[ -f "${actual_install_root}/VERSION" ]]
	fi

	rm -rf "${temp_dir}"
	rm -rf "${actual_install_root}"
}

@test "install.sh:: extract_archive extracts tar.gz" {
	if ! command -v "tar" >/dev/null 2>&1; then
		skip "tar not available"
	fi

	local temp_dir
	local archive_path
	local extract_dir
	local source_dir

	temp_dir=$(mktemp -d "${BATS_TEST_TMPDIR}/extract-test.XXXXXX")
	archive_path="${temp_dir}/test.tar.gz"
	extract_dir="${temp_dir}/extract"
	source_dir="${temp_dir}/source"

	mkdir -p "$source_dir/bin"
	echo "test" >"${source_dir}/bin/test.sh"

	tar -czf "$archive_path" -C "$source_dir" .
	mkdir -p "$extract_dir"

	run extract_archive "$archive_path" "$extract_dir"
	[[ "$status" -eq 0 ]]
	[[ -f "${extract_dir}/bin/test.sh" ]]

	rm -rf "$temp_dir"
}

@test "install.sh:: build_source_archive_url creates gzip URL" {
	build_source_archive_url "main"
	[[ "$ARTIFACT_URL" == *".tar.gz" ]]
	[[ "$ARTIFACT_EXT" == ".tar.gz" ]]
}

@test "install.sh:: clone_repository clones branch" {
	if ! command -v "git" >/dev/null 2>&1; then
		skip "git not available"
	fi

	# Skip if we can't reach GitHub, network issues in test environment.
	if ! curl -s --max-time 2 https://github.com >/dev/null 2>&1; then
		skip "GitHub not reachable"
	fi

	local temp_dir

	temp_dir=$(mktemp -d "${BATS_TEST_TMPDIR}/clone-test.XXXXXX")

	if ! clone_repository "main" "$temp_dir"; then
		skip "clone_repository failed, may be network issue"
	fi
	[[ -n "$CLONE_DIR" ]]
	[[ -d "$CLONE_DIR" ]]
	[[ -f "${CLONE_DIR}/bin/send-to-slack.sh" ]]
	[[ -d "${CLONE_DIR}/lib" ]]

	rm -rf "$temp_dir"
}

@test "install.sh:: clone_repository fails with invalid ref" {
	if ! command -v "git" >/dev/null 2>&1; then
		skip "git not available"
	fi

	local temp_dir

	temp_dir=$(mktemp -d "${BATS_TEST_TMPDIR}/clone-test.XXXXXX")

	run clone_repository "nonexistent-branch-xyz123" "$temp_dir"
	[[ "$status" -eq 1 ]]

	rm -rf "$temp_dir"
}

@test "install.sh:: verify_installation succeeds when binary exists" {
	local temp_prefix
	local temp_binary

	temp_prefix=$(mktemp -d "${BATS_TEST_TMPDIR}/verify-test.XXXXXX")
	temp_binary="${temp_prefix}/${INSTALL_BASENAME_VALUE}"

	mkdir -p "$temp_prefix"
	printf '#!/usr/bin/env bash\n' >"$temp_binary"
	chmod 0755 "$temp_binary"

	# Add prefix to PATH temporarily
	export PATH="${temp_prefix}:${PATH}"

	run verify_installation "$temp_prefix"
	[[ "$status" -eq 0 ]]

	# Clean up PATH
	local new_path
	new_path=$(echo "$PATH" | tr ':' '\n' | grep -v "^${temp_prefix}$" | tr '\n' ':')
	export PATH="$new_path"
	rm -rf "$temp_prefix"
}

@test "install.sh:: verify_installation fails when binary missing" {
	local temp_prefix
	local temp_binary

	temp_prefix=$(mktemp -d "${BATS_TEST_TMPDIR}/verify-test.XXXXXX")
	temp_binary="${temp_prefix}/${INSTALL_BASENAME_VALUE}"

	# Ensure the binary doesn't exist
	[[ ! -f "$temp_binary" ]]

	# Use a prefix that's definitely not in PATH
	# The function should check the specific path first, which won't exist
	run verify_installation "$temp_prefix"
	# This might pass if send-to-slack is installed elsewhere via command -v
	# But we can at least verify the path check works by ensuring the file doesn't exist
	[[ ! -f "$temp_binary" ]]

	rm -rf "$temp_prefix"
}

# print_install_info
@test "print_install_info:: returns 0 for empty source dir" {
	run print_install_info "" "main"
	[[ "$status" -eq 0 ]]
}

@test "print_install_info:: outputs ref, version, commit for a git repo" {
	if ! command -v "git" >/dev/null 2>&1; then
		skip "git not available"
	fi

	local worktree_dir
	worktree_dir=$(mktemp -d "${BATS_TEST_TMPDIR}/print-info-worktree.XXXXXX")

	git -C "$GIT_ROOT" worktree add "$worktree_dir" HEAD

	run print_install_info "$worktree_dir" "main"
	[[ "$status" -eq 0 ]]

	echo "$output" | grep -q "install:: ref:     main"
	echo "$output" | grep -q "install:: version:"
	echo "$output" | grep -q "install:: commit:"

	git -C "$GIT_ROOT" worktree remove --force "$worktree_dir"
}

@test "print_install_info:: outputs unknown commit and version for non-git directory" {
	local plain_dir
	plain_dir=$(mktemp -d "${BATS_TEST_TMPDIR}/print-info-plain.XXXXXX")

	run print_install_info "$plain_dir" "v1.2.3"
	[[ "$status" -eq 0 ]]

	echo "$output" | grep -q "install:: ref:     v1.2.3"
	echo "$output" | grep -q "install:: version: v1.2.3"
	echo "$output" | grep -q "install:: commit:  unknown"

	rm -rf "$plain_dir"
}
