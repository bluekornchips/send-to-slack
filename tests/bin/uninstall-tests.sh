#!/usr/bin/env bats
#
# Tests for uninstall.sh
#

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		echo "setup_file:: git root not found" >&2
		exit 1
	fi

	INSTALL_SCRIPT="${GIT_ROOT}/bin/install.sh"
	UNINSTALL_SCRIPT="${GIT_ROOT}/bin/uninstall.sh"

	if [[ ! -f "$INSTALL_SCRIPT" ]]; then
		echo "setup_file:: install script missing: $INSTALL_SCRIPT" >&2
		exit 1
	fi

	if [[ ! -f "$UNINSTALL_SCRIPT" ]]; then
		echo "setup_file:: uninstall script missing: $UNINSTALL_SCRIPT" >&2
		exit 1
	fi

	# shellcheck source=/dev/null
	source "$INSTALL_SCRIPT"

	INSTALL_SIGNATURE_VALUE="$INSTALL_SIGNATURE"
	INSTALL_BASENAME_VALUE="$INSTALL_BASENAME"

	export GIT_ROOT
	export INSTALL_SCRIPT
	export UNINSTALL_SCRIPT
	export INSTALL_SIGNATURE_VALUE
	export INSTALL_BASENAME_VALUE

	return 0
}

setup() {
	PREFIX_DIR="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/send-to-slack-uninstall.XXXXXX")"
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

@test "uninstall.sh:: removes signed binary" {
	run "$INSTALL_SCRIPT" --version local --prefix "$PREFIX_DIR"
	[[ "$status" -eq 0 ]]

	run "$UNINSTALL_SCRIPT" --prefix "$PREFIX_DIR"
	[[ "$status" -eq 0 ]]
	[[ ! -f "$TARGET_PATH" ]]
}

@test "uninstall.sh:: refuses unsigned binary" {
	printf '#!/usr/bin/env bash\n' >"$TARGET_PATH"
	chmod 0755 "$TARGET_PATH"

	run "$UNINSTALL_SCRIPT" --prefix "$PREFIX_DIR"
	[[ "$status" -eq 1 ]]
	[[ -f "$TARGET_PATH" ]]
}
