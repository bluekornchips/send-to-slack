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

	local tmp_root="${BATS_TEST_TMPDIR:-/tmp}"
	TEST_INSTALL_DIR=$(mktemp -d "${tmp_root}/test-install.XXXXXX")
	TEMP_HOME=$(mktemp -d "${tmp_root}/send-to-slack-home.XXXXXX")

	export TEST_INSTALL_DIR
	export GIT_ROOT
	export SCRIPT
	export TEMP_HOME

	return 0
}

setup() {
	return 0
}

########################################################
# Basic functionality
########################################################

@test "install:: uses default prefix when no argument provided" {
	run env HOME="$TEMP_HOME" "$SCRIPT"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Installed send-to-slack to"
	local expected_default="${TEMP_HOME}/.local/bin/send-to-slack"
	[[ -f "$expected_default" ]]
	rm -rf "${TEMP_HOME}/.local/bin/send-to-slack" "${TEMP_HOME}/.local/bin/blocks" "${TEMP_HOME}/.local/bin"/*.sh 2>/dev/null || true
	rmdir "${TEMP_HOME}/.local/bin/blocks" "${TEMP_HOME}/.local/bin" 2>/dev/null || true
}

@test "install:: accepts --path to set installation prefix" {
	run env HOME="$TEMP_HOME" "$SCRIPT" --path "$TEST_INSTALL_DIR"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "$TEST_INSTALL_DIR/bin/send-to-slack"
	[[ -x "$TEST_INSTALL_DIR/bin/send-to-slack" ]]
}

@test "install:: --commit installs specific commit from repo" {
	local tmp_root="${BATS_TEST_TMPDIR:-/tmp}"
	local repo_root
	local commit_ref
	local clone_prefix

	repo_root=$(mktemp -d "${tmp_root}/send-to-slack-repo.XXXXXX")
	clone_prefix=$(mktemp -d "${tmp_root}/send-to-slack-prefix.XXXXXX")

	mkdir -p "${repo_root}/bin/blocks" "${repo_root}/share/send-to-slack"

	cat <<'EOF' >"${repo_root}/send-to-slack.sh"
#!/usr/bin/env bash
exit 0
EOF
	chmod +x "${repo_root}/send-to-slack.sh"

	cat <<'EOF' >"${repo_root}/bin/parse-payload.sh"
#!/usr/bin/env bash
exit 0
EOF
	chmod +x "${repo_root}/bin/parse-payload.sh"

	cat <<'EOF' >"${repo_root}/bin/blocks/actions.sh"
#!/usr/bin/env bash
exit 0
EOF
	chmod +x "${repo_root}/bin/blocks/actions.sh"

	echo "v0.0.commit" >"${repo_root}/VERSION"

	pushd "$repo_root" >/dev/null || exit 1
	git init >/dev/null 2>&1
	git config user.email "test@example.com"
	git config user.name "Test User"
	git add .
	git commit -m "test commit" >/dev/null 2>&1
	commit_ref=$(git rev-parse HEAD)
	popd >/dev/null || true

	run env SEND_TO_SLACK_REPO_URL="$repo_root" HOME="$TEMP_HOME" "$SCRIPT" --commit "$commit_ref" --path "$clone_prefix"
	[[ "$status" -eq 0 ]]
	[[ -x "$clone_prefix/bin/send-to-slack" ]]
	[[ -f "$clone_prefix/share/send-to-slack/VERSION" ]]
	grep -q "v0.0.commit" "$clone_prefix/share/send-to-slack/VERSION"

	rm -rf "$repo_root" "$clone_prefix"
}

@test "install:: creates required directories" {
	run env HOME="$TEMP_HOME" "$SCRIPT" --path "$TEST_INSTALL_DIR"
	[[ "$status" -eq 0 ]]
	[[ -d "$TEST_INSTALL_DIR/bin/blocks" ]]
	[[ -d "$TEST_INSTALL_DIR/bin" ]]
}

@test "install:: copies main script to bin directory" {
	run env HOME="$TEMP_HOME" "$SCRIPT" "$TEST_INSTALL_DIR"
	[[ "$status" -eq 0 ]]
	[[ -f "$TEST_INSTALL_DIR/bin/send-to-slack" ]]
	[[ -x "$TEST_INSTALL_DIR/bin/send-to-slack" ]]
}

@test "install:: copies source files to bin directory" {
	run env HOME="$TEMP_HOME" "$SCRIPT" "$TEST_INSTALL_DIR"
	[[ "$status" -eq 0 ]]
	[[ -f "$TEST_INSTALL_DIR/bin/parse-payload.sh" ]]
	[[ -f "$TEST_INSTALL_DIR/bin/file-upload.sh" ]]
	[[ -f "$TEST_INSTALL_DIR/bin/resolve-mentions.sh" ]]
}

@test "install:: copies blocks directory" {
	run env HOME="$TEMP_HOME" "$SCRIPT" "$TEST_INSTALL_DIR"
	[[ "$status" -eq 0 ]]
	[[ -d "$TEST_INSTALL_DIR/bin/blocks" ]]
	[[ -f "$TEST_INSTALL_DIR/bin/blocks/actions.sh" ]]
	[[ -f "$TEST_INSTALL_DIR/bin/blocks/rich-text.sh" ]]
}

@test "install:: sets execute permissions on all scripts" {
	run env HOME="$TEMP_HOME" "$SCRIPT" "$TEST_INSTALL_DIR"
	[[ "$status" -eq 0 ]]
	[[ -x "$TEST_INSTALL_DIR/bin/parse-payload.sh" ]]
	[[ -x "$TEST_INSTALL_DIR/bin/blocks/actions.sh" ]]
}

@test "install:: outputs installation location" {
	run env HOME="$TEMP_HOME" "$SCRIPT" "$TEST_INSTALL_DIR"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Installed send-to-slack to"
	echo "$output" | grep -q "$TEST_INSTALL_DIR/bin/send-to-slack"
}

@test "install:: handles prefix with trailing slash" {
	run env HOME="$TEMP_HOME" "$SCRIPT" "$TEST_INSTALL_DIR/"
	[[ "$status" -eq 0 ]]
	[[ -f "$TEST_INSTALL_DIR/bin/send-to-slack" ]]
}

@test "install:: writes manifest with installed files" {
	run env HOME="$TEMP_HOME" "$SCRIPT" "$TEST_INSTALL_DIR"
	[[ "$status" -eq 0 ]]
	local manifest
	manifest="$TEST_INSTALL_DIR/share/send-to-slack/install_manifest.txt"
	[[ -f "$manifest" ]]
	grep -q "$TEST_INSTALL_DIR/bin/send-to-slack" "$manifest"
	grep -q "$TEST_INSTALL_DIR/bin/parse-payload.sh" "$manifest"
	grep -q "$TEST_INSTALL_DIR/bin/blocks/actions.sh" "$manifest"
}

@test "install:: writes version file to share directory" {
	run env HOME="$TEMP_HOME" "$SCRIPT" "$TEST_INSTALL_DIR"
	[[ "$status" -eq 0 ]]
	local version_path
	version_path="$TEST_INSTALL_DIR/share/send-to-slack/VERSION"
	[[ -f "$version_path" ]]
	local installed_version
	local source_version
	installed_version=$(cat "$version_path")
	source_version=$(cat "$GIT_ROOT/VERSION")
	[[ "$installed_version" == "$source_version" ]]
}

@test "install:: installs into provided prefix in isolated shell" {
	local prefix
	local tmp_root="${BATS_TEST_TMPDIR:-/tmp}"
	prefix=$(mktemp -d "${tmp_root}/send-to-slack-prefix.XXXXXX")
	run env HOME="$TEMP_HOME" bash -c "cd \"$GIT_ROOT\" && \"$SCRIPT\" \"$prefix\""
	[[ "$status" -eq 0 ]]
	[[ -x "$prefix/bin/send-to-slack" ]]
	[[ -f "$prefix/share/send-to-slack/install_manifest.txt" ]]
	rm -rf "$prefix"
}
