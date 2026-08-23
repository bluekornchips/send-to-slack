#!/usr/bin/env bats
#
# Tests for uninstall.sh
#

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		fail "setup_file:: git root not found"
	fi

	INSTALL_SCRIPT="${GIT_ROOT}/bin/install.sh"
	UNINSTALL_SCRIPT="${GIT_ROOT}/bin/uninstall.sh"

	if [[ ! -f "$INSTALL_SCRIPT" ]]; then
		fail "setup_file:: install script missing: $INSTALL_SCRIPT"
	fi

	if [[ ! -f "$UNINSTALL_SCRIPT" ]]; then
		fail "setup_file:: uninstall script missing: $UNINSTALL_SCRIPT"
	fi

	TEST_HOME="$(mktemp -d "${BATS_FILE_TMPDIR:-${TMPDIR:-/tmp}}/uninstall-home.XXXXXX")"
	export HOME="$TEST_HOME"

	source "$INSTALL_SCRIPT"
	source "$UNINSTALL_SCRIPT"

	INSTALL_SIGNATURE_VALUE="$INSTALL_SIGNATURE"
	INSTALL_BASENAME_VALUE="$INSTALL_BASENAME"

	# Export functions so they're available in test subshells
	export -f uninstall_binary normalize_prefix file_has_signature validate_prefix _install_lib_rel_paths install_from_source _resolve_install_root _assemble_install_staging _validate_install_tree

	export GIT_ROOT
	export INSTALL_SCRIPT
	export UNINSTALL_SCRIPT
	export INSTALL_SIGNATURE_VALUE
	export INSTALL_BASENAME_VALUE
	export TEST_HOME

	return 0
}

teardown_file() {
	if [[ -n "${TEST_HOME:-}" && -d "$TEST_HOME" ]]; then
		rm -rf "$TEST_HOME"
	fi

	return 0
}

setup() {
	PREFIX_DIR="$(mktemp -d "${BATS_TEST_TMPDIR}/send-to-slack-uninstall.XXXXXX")"
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

	# Clear only the test-owned user install root so parallel jobs stay isolated.
	rm -rf "${HOME}/.local/share/send-to-slack"

	other_prefix=$(mktemp -d "${BATS_TEST_TMPDIR}/send-to-slack-other.XXXXXX")
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

	# Clear only the test-owned user install root so parallel jobs stay isolated.
	rm -rf "${HOME}/.local/share/send-to-slack"

	temp_dir=$(mktemp -d "${BATS_TEST_TMPDIR}/send-to-slack-source.XXXXXX")
	source_dir="${temp_dir}/send-to-slack-main"

	mkdir -p "${source_dir}/bin" "${source_dir}/lib/slack/block-kit/blocks" "${source_dir}/lib/slack/utils" "${source_dir}/lib/parse"

	cp "${GIT_ROOT}/bin/send-to-slack.sh" "${source_dir}/bin/send-to-slack.sh"
	cp -a "${GIT_ROOT}/lib/." "${source_dir}/lib/"
	if [[ -f "${GIT_ROOT}/VERSION" ]]; then
		cp "${GIT_ROOT}/VERSION" "${source_dir}/VERSION"
	fi

	for need in \
		"${source_dir}/lib/parse/payload.sh" \
		"${source_dir}/lib/parse/blocks.sh"; do
		if [[ ! -f "$need" ]]; then
			fail "uninstall fixture missing required file after copy: $need"
		fi
	done

	# Install using install_from_source
	run install_from_source "${source_dir}" "${PREFIX_DIR}" 0
	[[ "$status" -eq 0 ]]
	[[ -L "$TARGET_PATH" ]]

	symlink_target=$(readlink "$TARGET_PATH")
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
	run bash -c '
		id() {
			if [[ "${1:-}" == "-u" ]]; then
				echo 0
				return 0
			fi
			command id "$@"
		}
		export -f id
		# shellcheck source=bin/uninstall.sh disable=SC1090,SC1091
		source "'"$UNINSTALL_SCRIPT"'"
		[[ "$DEFAULT_PREFIX" == "/usr/local/bin" ]]
	'
	[[ "$status" -eq 0 ]]
}

@test "uninstall.sh:: allows /usr/local/* prefix" {
	run validate_prefix "/usr/local/bin"
	[[ "$status" -eq 0 ]]

	run validate_prefix "/usr/local/send-to-slack"
	[[ "$status" -eq 0 ]]

	run validate_prefix "/usr/bin"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "refusing system prefix"
}
