#!/usr/bin/env bats
#
# Test file for uninstall.sh
#

cleanup() {
	rm -rf "${TEST_INSTALL_DIR:-}" "${TEST_PREFIX:-}" "${TEST_BIN_DIR:-}"
	rm -rf "${BATS_TEST_TMPDIR:-/tmp}"/uninstall-tests.*
}
trap cleanup EXIT

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		echo "Failed to get git root" >&2
		exit 1
	fi

	UNINSTALL_SCRIPT="$GIT_ROOT/bin/uninstall.sh"
	if [[ ! -f "$UNINSTALL_SCRIPT" ]]; then
		echo "Script not found: $UNINSTALL_SCRIPT" >&2
		exit 1
	fi

	local tmp_root="${BATS_TEST_TMPDIR:-/tmp}"
	TEST_PREFIX=$(mktemp -d "${tmp_root}/uninstall-tests.prefix.XXXXXX")
	TEST_INSTALL_DIR="$TEST_PREFIX/send-to-slack"
	TEST_BIN_DIR="$TEST_PREFIX/bin"

	mkdir -p "$TEST_INSTALL_DIR/lib/blocks" "$TEST_BIN_DIR"

	export UNINSTALL_SCRIPT
	export TEST_PREFIX
	export TEST_INSTALL_DIR
	export TEST_BIN_DIR
	export GIT_ROOT

	return 0
}

teardown_file() {
	rm -rf "${TEST_INSTALL_DIR}" "${TEST_PREFIX}" "${TEST_BIN_DIR}"
}

setup() {
	# Create a fresh installation for each test (recreate if removed by previous test)
	mkdir -p "$TEST_INSTALL_DIR/lib/blocks" "$TEST_BIN_DIR"

	# Create send-to-slack executable
	echo "#!/usr/bin/env bash" >"$TEST_INSTALL_DIR/send-to-slack"
	echo "echo test" >>"$TEST_INSTALL_DIR/send-to-slack"
	chmod +x "$TEST_INSTALL_DIR/send-to-slack"

	# Create lib files
	echo "#!/usr/bin/env bash" >"$TEST_INSTALL_DIR/lib/parse-payload.sh"
	echo "echo test" >>"$TEST_INSTALL_DIR/lib/parse-payload.sh"
	chmod +x "$TEST_INSTALL_DIR/lib/parse-payload.sh"

	echo "#!/usr/bin/env bash" >"$TEST_INSTALL_DIR/lib/blocks/actions.sh"
	echo "echo test" >>"$TEST_INSTALL_DIR/lib/blocks/actions.sh"
	chmod +x "$TEST_INSTALL_DIR/lib/blocks/actions.sh"

	# Create VERSION file
	echo "0.1.2" >"$TEST_INSTALL_DIR/VERSION"

	# Copy executable to bin/ for PATH access
	cp "$TEST_INSTALL_DIR/send-to-slack" "$TEST_BIN_DIR/send-to-slack"

	return 0
}

teardown() {
	# Clean up after each test - remove executable but keep directories for next test
	rm -f "$TEST_BIN_DIR/send-to-slack" 2>/dev/null || true
	return 0
}

run_uninstaller() {
	local args=("$@")
	local old_path="$PATH"
	export PATH="$TEST_BIN_DIR:$PATH"
	run bash -c "\"$UNINSTALL_SCRIPT\" ${args[*]}"
	local exit_code=$?
	export PATH="$old_path"
	return $exit_code
}

########################################################
# Basic functionality
########################################################

@test "uninstall:: --help shows usage information" {
	run_uninstaller --help
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "usage:"
	echo "$output" | grep -q "uninstall"
}

@test "uninstall:: handles unknown options" {
	run_uninstaller --unknown-option
	[[ "$status" -ne 0 ]]
	echo "$output" | grep -q "unknown option"
}

@test "uninstall:: auto-detects installation directory" {
	run_uninstaller
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "removed installation directory"
	[[ ! -d "$TEST_INSTALL_DIR" ]]
}

@test "uninstall:: removes executable when auto-detecting" {
	run_uninstaller
	[[ "$status" -eq 0 ]]
	[[ ! -f "$TEST_BIN_DIR/send-to-slack" ]]
}

@test "uninstall:: works with prefix argument" {
	run_uninstaller "$TEST_PREFIX"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "removed installation directory"
	[[ ! -d "$TEST_INSTALL_DIR" ]]
}

@test "uninstall:: validates installation directory exists" {
	rm -rf "$TEST_INSTALL_DIR"
	run_uninstaller "$TEST_PREFIX"
	[[ "$status" -ne 0 ]]
	echo "$output" | grep -q "installation directory not found"
}

@test "uninstall:: validates send-to-slack executable exists" {
	rm -f "$TEST_INSTALL_DIR/send-to-slack"
	run_uninstaller "$TEST_PREFIX"
	[[ "$status" -ne 0 ]]
	echo "$output" | grep -q "send-to-slack executable not found"
}

@test "uninstall:: validates lib directory exists" {
	rm -rf "${TEST_INSTALL_DIR:?}/lib"
	run_uninstaller "$TEST_PREFIX"
	[[ "$status" -ne 0 ]]
	echo "$output" | grep -q "lib directory not found"
}

@test "uninstall:: requires --force for protected prefixes" {
	local protected_prefix="/usr/local"
	# Skip if we can't create the directory
	if mkdir -p "$protected_prefix/send-to-slack/lib" 2>/dev/null; then
		echo "#!/usr/bin/env bash" >"$protected_prefix/send-to-slack/send-to-slack"
		chmod +x "$protected_prefix/send-to-slack/send-to-slack"
		run_uninstaller "$protected_prefix"
		[[ "$status" -ne 0 ]]
		echo "$output" | grep -q "refusing to uninstall from protected prefix"
		rm -rf "$protected_prefix/send-to-slack" 2>/dev/null || true
	fi
}

@test "uninstall:: --force allows uninstalling from protected prefixes" {
	local protected_prefix="/usr/local"
	# Skip if we can't create the directory
	if mkdir -p "$protected_prefix/send-to-slack/lib" 2>/dev/null; then
		echo "#!/usr/bin/env bash" >"$protected_prefix/send-to-slack/send-to-slack"
		chmod +x "$protected_prefix/send-to-slack/send-to-slack"
		run_uninstaller --force "$protected_prefix"
		[[ "$status" -eq 0 ]]
		[[ ! -d "$protected_prefix/send-to-slack" ]]
		rm -rf "$protected_prefix/send-to-slack" 2>/dev/null || true
	fi
}

@test "uninstall:: fails when send-to-slack command not found in PATH" {
	# Mock command -v to return nothing for send-to-slack
	command() {
		if [[ "$1" == "-v" ]] && [[ "$2" == "send-to-slack" ]]; then
			return 1
		fi
		builtin command "$@"
	}
	export -f command
	run bash -c "\"$UNINSTALL_SCRIPT\""
	unset -f command
	[[ "$status" -ne 0 ]]
	echo "$output" | grep -q "send-to-slack command not found"
}

@test "uninstall:: handles multiple prefix arguments" {
	run_uninstaller "$TEST_PREFIX" "/another/prefix"
	[[ "$status" -ne 0 ]]
	echo "$output" | grep -q "multiple prefix arguments provided"
}
