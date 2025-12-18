#!/usr/bin/env bats
#
# Tests for install.sh
#

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		echo "setup_file:: git root not found" >&2
		exit 1
	fi

	INSTALL_SCRIPT="${GIT_ROOT}/bin/install.sh"

	if [[ ! -f "$INSTALL_SCRIPT" ]]; then
		echo "setup_file:: install script missing: $INSTALL_SCRIPT" >&2
		exit 1
	fi

	# shellcheck source=/dev/null
	source "$INSTALL_SCRIPT"

	INSTALL_SIGNATURE_VALUE="$INSTALL_SIGNATURE"
	INSTALL_BASENAME_VALUE="$INSTALL_BASENAME"

	export GIT_ROOT
	export INSTALL_SCRIPT
	export INSTALL_SIGNATURE_VALUE
	export INSTALL_BASENAME_VALUE

	return 0
}

setup() {
	PREFIX_DIR="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/send-to-slack-install.XXXXXX")"
	TARGET_PATH="${PREFIX_DIR}/${INSTALL_BASENAME_VALUE}"

	export PREFIX_DIR
	export TARGET_PATH

	return 0
}

teardown() {
	if [[ -n "$TARGET_PATH" && -f "$TARGET_PATH" ]]; then
		rm -f "$TARGET_PATH"
	fi

	if [[ -n "$PREFIX_DIR" && -d "$PREFIX_DIR" ]]; then
		rm -rf "$PREFIX_DIR"
	fi

	return 0
}

@test "install.sh:: installs binary with signature and mode (local)" {
	run "$INSTALL_SCRIPT" --version local --prefix "$PREFIX_DIR"
	[[ "$status" -eq 0 ]]

	[[ -f "$TARGET_PATH" ]]
	[[ -x "$TARGET_PATH" ]]
	grep -Fq "$INSTALL_SIGNATURE_VALUE" "$TARGET_PATH"
}

@test "install.sh:: reinstall is idempotent (local)" {
	run "$INSTALL_SCRIPT" --version local --prefix "$PREFIX_DIR"
	[[ "$status" -eq 0 ]]

	run "$INSTALL_SCRIPT" --version local --prefix "$PREFIX_DIR"
	[[ "$status" -eq 0 ]]

	sig_count=$(grep -c "$INSTALL_SIGNATURE_VALUE" "$TARGET_PATH")
	[[ "$sig_count" -eq 1 ]]
}

@test "install.sh:: supports container-style prefix (local)" {
	local container_prefix
	local container_target

	container_prefix="${BATS_TEST_TMPDIR:-/tmp}/container/user/bin"
	container_target="${container_prefix}/${INSTALL_BASENAME_VALUE}"

	run "$INSTALL_SCRIPT" --version local --prefix "$container_prefix"
	[[ "$status" -eq 0 ]]
	[[ -f "$container_target" ]]
	grep -Fq "$INSTALL_SIGNATURE_VALUE" "$container_target"

	rm -rf "$container_prefix"
}

@test "install.sh:: usage displays help" {
	run "$INSTALL_SCRIPT" --help
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Usage:"
}
