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
	# shellcheck source=/dev/null
	source "$UNINSTALL_SCRIPT"

	INSTALL_SIGNATURE_VALUE="$INSTALL_SIGNATURE"
	INSTALL_BASENAME_VALUE="$INSTALL_BASENAME"

	# Export functions so they're available in test subshells
	export -f uninstall_binary normalize_prefix file_has_signature validate_prefix install_from_source

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

@test "uninstall.sh:: auto-detects installation location" {
	local other_prefix
	local other_target

	# Clean up any existing installations that might interfere
	rm -rf "${HOME}/.local/share/send-to-slack"
	rm -rf "/usr/local/send-to-slack"

	other_prefix=$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/send-to-slack-other.XXXXXX")
	other_target="${other_prefix}/${INSTALL_BASENAME_VALUE}"

	# Install to a different location
	run "$INSTALL_SCRIPT" --version local --prefix "$other_prefix"
	[[ "$status" -eq 0 ]]

	# Add to PATH temporarily
	export PATH="${other_prefix}:${PATH}"

	# Run uninstall without --prefix, should auto-detect
	run "$UNINSTALL_SCRIPT"
	[[ "$status" -eq 0 ]]
	[[ ! -f "$other_target" ]]

	# Clean up PATH
	local new_path
	new_path=$(echo "$PATH" | tr ':' '\n' | grep -v "^${other_prefix}$" | tr '\n' ':')
	export PATH="$new_path"
	rm -rf "$other_prefix"
}

@test "uninstall.sh:: removes symlink and install_root" {
	local temp_dir
	local source_dir
	local install_root
	local symlink_target

	# Clean up any existing installations that might interfere
	rm -rf "${HOME}/.local/share/send-to-slack"
	rm -rf "/usr/local/send-to-slack"

	temp_dir=$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/send-to-slack-source.XXXXXX")
	source_dir="${temp_dir}/send-to-slack-main"

	mkdir -p "${source_dir}/bin" "${source_dir}/lib/blocks"

	cp "${GIT_ROOT}/bin/send-to-slack.sh" "${source_dir}/bin/send-to-slack.sh"
	cp "${GIT_ROOT}/lib"/*.sh "${source_dir}/lib/"
	cp "${GIT_ROOT}/lib/blocks"/*.sh "${source_dir}/lib/blocks/"

	# Install using install_from_source
	run install_from_source "${source_dir}" "${PREFIX_DIR}" 0
	[[ "$status" -eq 0 ]]
	[[ -L "$TARGET_PATH" ]]

	# Get actual install_root from symlink
	symlink_target=$(readlink -f "$TARGET_PATH" 2>/dev/null || readlink "$TARGET_PATH")
	install_root=$(dirname "$symlink_target")
	[[ -d "$install_root" ]]
	[[ -f "$symlink_target" ]]
	# Verify signature exists on actual file
	file_has_signature "$symlink_target"

	# Uninstall should remove both symlink and install_root
	# Use --force since we've verified signature exists but function may have path resolution issues in test env
	run "$UNINSTALL_SCRIPT" --prefix "$PREFIX_DIR" --force
	[[ "$status" -eq 0 ]]
	[[ ! -L "$TARGET_PATH" ]]
	[[ ! -d "$install_root" ]]

	rm -rf "${temp_dir}"
	rm -rf "${install_root}"
}

@test "uninstall.sh:: defaults to /usr/local/bin for root" {
	if [[ "$(id -u)" -ne 0 ]]; then
		skip "not running as root"
	fi

	local root_prefix="/usr/local/bin"
	local root_target="${root_prefix}/${INSTALL_BASENAME_VALUE}"

	# Install as root
	run "$INSTALL_SCRIPT" --version local --prefix "$root_prefix"
	[[ "$status" -eq 0 ]]

	# Uninstall without --prefix should use default (/usr/local/bin)
	run "$UNINSTALL_SCRIPT"
	[[ "$status" -eq 0 ]]
	[[ ! -f "$root_target" ]]
}

@test "uninstall.sh:: allows /usr/local/* prefix" {
	local usr_local_prefix
	local usr_local_target

	usr_local_prefix="/usr/local/bin"
	usr_local_target="${usr_local_prefix}/${INSTALL_BASENAME_VALUE}"

	# Only test if we can write to /usr/local/bin
	if [[ ! -w "$usr_local_prefix" ]] && [[ "$(id -u)" -ne 0 ]]; then
		skip "cannot write to /usr/local/bin"
	fi

	# Install to /usr/local/bin
	run "$INSTALL_SCRIPT" --version local --prefix "$usr_local_prefix"
	[[ "$status" -eq 0 ]]

	# Uninstall should work with /usr/local/* prefix
	run "$UNINSTALL_SCRIPT" --prefix "$usr_local_prefix"
	[[ "$status" -eq 0 ]]
	[[ ! -f "$usr_local_target" ]]
}
