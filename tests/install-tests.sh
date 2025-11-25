#!/usr/bin/env bats
#
# Test file for install.sh
#

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		echo "Failed to get git root" >&2
		exit 1
	fi

	SCRIPT="$GIT_ROOT/install.sh"
	if [[ ! -f "$SCRIPT" ]]; then
		echo "Script not found: $SCRIPT" >&2
		exit 1
	fi

	TEST_INSTALL_DIR=$(mktemp -d test-install.XXXXXX)
	export TEST_INSTALL_DIR
	export GIT_ROOT
	export SCRIPT

	return 0
}

setup() {
	return 0
}

teardown_file() {
	if [[ -n "$TEST_INSTALL_DIR" ]] && [[ -d "$TEST_INSTALL_DIR" ]]; then
		rm -rf "$TEST_INSTALL_DIR"
	fi

	return 0
}

########################################################
# Basic functionality
########################################################

@test "install:: uses default prefix when no argument provided" {
	run "$SCRIPT"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Installed send-to-slack to"
	# Verify it installed to the default location
	local expected_default="${HOME}/.local/bin/send-to-slack"
	[[ -f "$expected_default" ]]
	# Clean up default installation
	rm -rf "${HOME}/.local/bin/send-to-slack" "${HOME}/.local/bin/blocks" "${HOME}/.local/bin"/*.sh 2>/dev/null || true
	rmdir "${HOME}/.local/bin/blocks" "${HOME}/.local/bin" 2>/dev/null || true
}

@test "install:: creates required directories" {
	run "$SCRIPT" "$TEST_INSTALL_DIR"
	[[ "$status" -eq 0 ]]

	[[ -d "$TEST_INSTALL_DIR/bin/blocks" ]]
	[[ -d "$TEST_INSTALL_DIR/bin" ]]
}

@test "install:: copies main script to bin directory" {
	run "$SCRIPT" "$TEST_INSTALL_DIR"
	[[ "$status" -eq 0 ]]

	[[ -f "$TEST_INSTALL_DIR/bin/send-to-slack" ]]
	[[ -x "$TEST_INSTALL_DIR/bin/send-to-slack" ]]
}

@test "install:: copies source files to bin directory" {
	run "$SCRIPT" "$TEST_INSTALL_DIR"
	[[ "$status" -eq 0 ]]

	[[ -f "$TEST_INSTALL_DIR/bin/parse-payload.sh" ]]
	[[ -f "$TEST_INSTALL_DIR/bin/file-upload.sh" ]]
	[[ -f "$TEST_INSTALL_DIR/bin/resolve-mentions.sh" ]]
}

@test "install:: copies blocks directory" {
	run "$SCRIPT" "$TEST_INSTALL_DIR"
	[[ "$status" -eq 0 ]]

	[[ -d "$TEST_INSTALL_DIR/bin/blocks" ]]
	[[ -f "$TEST_INSTALL_DIR/bin/blocks/actions.sh" ]]
	[[ -f "$TEST_INSTALL_DIR/bin/blocks/rich-text.sh" ]]
}

@test "install:: sets execute permissions on all scripts" {
	run "$SCRIPT" "$TEST_INSTALL_DIR"
	[[ "$status" -eq 0 ]]

	local script_file
	script_file="$TEST_INSTALL_DIR/bin/parse-payload.sh"
	[[ -x "$script_file" ]]

	script_file="$TEST_INSTALL_DIR/bin/blocks/actions.sh"
	[[ -x "$script_file" ]]
}

@test "install:: outputs installation location" {
	run "$SCRIPT" "$TEST_INSTALL_DIR"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Installed send-to-slack to"
	echo "$output" | grep -q "$TEST_INSTALL_DIR/bin/send-to-slack"
}

@test "install:: handles prefix with trailing slash" {
	run "$SCRIPT" "$TEST_INSTALL_DIR/"
	[[ "$status" -eq 0 ]]

	[[ -f "$TEST_INSTALL_DIR/bin/send-to-slack" ]]
}
