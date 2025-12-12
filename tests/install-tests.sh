#!/usr/bin/env bats
#
# Test file for install.sh
#

cleanup() {
	rm -rf "${TEST_INSTALL_DIR:-}" "${TEMP_HOME:-}" "${FIXTURE_DIR:-}" "${SHIM_DIR:-}"
	rm -rf "${BATS_TEST_TMPDIR:-/tmp}"/install-tests.*
}
trap cleanup EXIT

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
	TEST_INSTALL_DIR=$(mktemp -d "${tmp_root}/install-tests.test-install.XXXXXX")
	TEMP_HOME=$(mktemp -d "${tmp_root}/install-tests.home.XXXXXX")
	FIXTURE_DIR=$(mktemp -d "${tmp_root}/install-tests.fixtures.XXXXXX")
	SHIM_DIR=$(mktemp -d "${tmp_root}/install-tests.shims.XXXXXX")

	# safe .git dir, because omg
	mkdir -p "${TEMP_HOME}"
	git config --global --add safe.directory "$GIT_ROOT" 2>/dev/null || true
	HOME="$TEMP_HOME" git config --global --add safe.directory "$GIT_ROOT" 2>/dev/null || true

	export TEST_INSTALL_DIR
	export GIT_ROOT
	export SCRIPT
	export TEMP_HOME
	export FIXTURE_DIR
	export SHIM_DIR

	local fixture_repo_dir
	fixture_repo_dir="${FIXTURE_DIR}/send-to-slack-fixture"
	mkdir -p "${fixture_repo_dir}/bin/blocks"

	echo "#!/usr/bin/env bash" >"${fixture_repo_dir}/send-to-slack.sh"
	echo "echo test" >>"${fixture_repo_dir}/send-to-slack.sh"
	chmod +x "${fixture_repo_dir}/send-to-slack.sh"

	echo "#!/usr/bin/env bash" >"${fixture_repo_dir}/bin/parse-payload.sh"
	echo "echo test" >>"${fixture_repo_dir}/bin/parse-payload.sh"
	chmod +x "${fixture_repo_dir}/bin/parse-payload.sh"

	echo "#!/usr/bin/env bash" >"${fixture_repo_dir}/bin/file-upload.sh"
	echo "echo test" >>"${fixture_repo_dir}/bin/file-upload.sh"
	chmod +x "${fixture_repo_dir}/bin/file-upload.sh"

	echo "#!/usr/bin/env bash" >"${fixture_repo_dir}/bin/resolve-mentions.sh"
	echo "echo test" >>"${fixture_repo_dir}/bin/resolve-mentions.sh"
	chmod +x "${fixture_repo_dir}/bin/resolve-mentions.sh"

	echo "#!/usr/bin/env bash" >"${fixture_repo_dir}/bin/blocks/actions.sh"
	echo "echo test" >>"${fixture_repo_dir}/bin/blocks/actions.sh"
	chmod +x "${fixture_repo_dir}/bin/blocks/actions.sh"

	echo "#!/usr/bin/env bash" >"${fixture_repo_dir}/bin/blocks/rich-text.sh"
	echo "echo test" >>"${fixture_repo_dir}/bin/blocks/rich-text.sh"
	chmod +x "${fixture_repo_dir}/bin/blocks/rich-text.sh"

	echo "0.1.2" >"${fixture_repo_dir}/VERSION"

	FIXTURE_COMMIT_SHA="a1b2c3d4e5f6789012345678901234567890abcd"
	FIXTURE_TAG="v0.1.2"

	pushd "${FIXTURE_DIR}" >/dev/null || exit 1
	tar -czf "${FIXTURE_DIR}/fixture.tar.gz" -C "${FIXTURE_DIR}" send-to-slack-fixture
	popd >/dev/null || true

	if command -v sha256sum >/dev/null 2>&1; then
		FIXTURE_CHECKSUM=$(sha256sum "${FIXTURE_DIR}/fixture.tar.gz" | cut -d' ' -f1)
	elif command -v shasum >/dev/null 2>&1; then
		FIXTURE_CHECKSUM=$(shasum -a 256 "${FIXTURE_DIR}/fixture.tar.gz" | cut -d' ' -f1)
	else
		FIXTURE_CHECKSUM="test-checksum-placeholder"
	fi

	echo "${FIXTURE_CHECKSUM}  fixture.tar.gz" >"${FIXTURE_DIR}/checksums.sha256"

	cat >"${SHIM_DIR}/curl" <<CURLSHIM
#!/usr/bin/env bash
# Simple curl shim: find URL and -o flag, copy fixture
url=""
output=""
prev=""
for arg in "\$@"; do
	if [[ "\$prev" == "-o" ]]; then
		output="\$arg"
	fi
	if [[ "\$arg" == http* ]]; then
		url="\$arg"
	fi
	prev="\$arg"
done

if [[ -z "\$output" ]]; then
	exit 1
fi

if [[ "\$url" == *"/api.github.com/repos"*"/commits/"* ]]; then
	echo "{\"sha\":\"${FIXTURE_COMMIT_SHA}\"}" >"\$output"
elif [[ "\$url" == *".tar.gz" ]]; then
	cp "${FIXTURE_DIR}/fixture.tar.gz" "\$output"
elif [[ "\$url" == *"/checksums.sha256" ]]; then
	cp "${FIXTURE_DIR}/checksums.sha256" "\$output"
else
	exit 1
fi
CURLSHIM

	chmod +x "${SHIM_DIR}/curl"

	local real_tar_path
	real_tar_path=$(command -v tar)
	cat >"${SHIM_DIR}/tar" <<TARSHIM
#!/usr/bin/env bash
if [[ "\$1" == "-xzf" ]]; then
	cp "${FIXTURE_DIR}/fixture.tar.gz" "\$2"
	"${real_tar_path}" -xzf "\$2" -C "\$4"
else
	"${real_tar_path}" "\$@"
fi
TARSHIM

	chmod +x "${SHIM_DIR}/tar"

	export FIXTURE_COMMIT_SHA
	export FIXTURE_TAG
	export FIXTURE_CHECKSUM

	return 0
}

teardown_file() {
	rm -rf "${TEST_INSTALL_DIR}" "${TEMP_HOME}" "${FIXTURE_DIR}" "${SHIM_DIR}"
}

setup() {
	return 0
}

########################################################
# Mocks
########################################################

mock_network_tools() {
	export PATH="${SHIM_DIR}:${PATH}"
}

run_in_repo() {
	local args=("$@")
	run env HOME="$TEMP_HOME" bash -c "cd \"$GIT_ROOT\" && \"$SCRIPT\" ${args[*]}"
}

########################################################
# Basic functionality
########################################################

@test "install:: uses default prefix when no argument provided" {
	run_in_repo
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Installed send-to-slack to"
	local expected_default="${TEMP_HOME}/.local/bin/send-to-slack"
	[[ -f "$expected_default" ]]
	rm -rf "${TEMP_HOME}/.local/bin/send-to-slack" "${TEMP_HOME}/.local/bin/blocks" "${TEMP_HOME}/.local/bin"/*.sh 2>/dev/null || true
	rmdir "${TEMP_HOME}/.local/bin/blocks" "${TEMP_HOME}/.local/bin" 2>/dev/null || true
}

@test "install:: accepts --path to set installation prefix" {
	run_in_repo --path "$TEST_INSTALL_DIR"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "$TEST_INSTALL_DIR/bin/send-to-slack"
	[[ -x "$TEST_INSTALL_DIR/bin/send-to-slack" ]]
}

@test "install:: --local installs from local git repository" {
	local tmp_root="${BATS_TEST_TMPDIR:-/tmp}"
	local clone_prefix
	clone_prefix=$(mktemp -d "${tmp_root}/install-tests.prefix.XXXXXX")

	run_in_repo --local --path "$clone_prefix"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Installed send-to-slack to"
	echo "$output" | grep -q "Resolved reference"
	[[ -x "$clone_prefix/bin/send-to-slack" ]]
	[[ -f "$clone_prefix/share/send-to-slack/VERSION" ]]

	rm -rf "$clone_prefix"
}

@test "install:: --local fails when not in git repository" {
	local tmp_root="${BATS_TEST_TMPDIR:-/tmp}"
	local clone_prefix
	local non_git_dir
	clone_prefix=$(mktemp -d "${tmp_root}/install-tests.prefix.XXXXXX")
	non_git_dir=$(mktemp -d "${tmp_root}/install-tests.nongit.XXXXXX")

	run env HOME="$TEMP_HOME" bash -c "cd \"$non_git_dir\" && \"$SCRIPT\" --local --path \"$clone_prefix\""
	[[ "$status" -ne 0 ]]
	echo "$output" | grep -q "not in a git repository"

	rm -rf "$clone_prefix" "$non_git_dir"
}

@test "install:: --commit requires a value" {
	run env HOME="$TEMP_HOME" "$SCRIPT" --commit
	[[ "$status" -ne 0 ]]
	echo "$output" | grep -q "requires a value"
}

@test "install:: --commit installs specific commit" {
	mock_network_tools
	run env HOME="$TEMP_HOME" "$SCRIPT" --commit "$FIXTURE_TAG" --path "$TEST_INSTALL_DIR"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Installed send-to-slack to"
	[[ -x "$TEST_INSTALL_DIR/bin/send-to-slack" ]]
	[[ -f "$TEST_INSTALL_DIR/share/send-to-slack/VERSION" ]]
}

@test "install:: --local and --commit cannot be used together" {
	run env HOME="$TEMP_HOME" "$SCRIPT" --local --commit v0.1.0
	[[ "$status" -ne 0 ]]
	echo "$output" | grep -q "cannot be used with other install modes"
}

@test "install:: creates required directories" {
	run_in_repo --path "$TEST_INSTALL_DIR"
	[[ "$status" -eq 0 ]]
	[[ -d "$TEST_INSTALL_DIR/bin/blocks" ]]
	[[ -d "$TEST_INSTALL_DIR/bin" ]]
}

@test "install:: copies main script to bin directory" {
	run_in_repo "$TEST_INSTALL_DIR"
	[[ "$status" -eq 0 ]]
	[[ -f "$TEST_INSTALL_DIR/bin/send-to-slack" ]]
	[[ -x "$TEST_INSTALL_DIR/bin/send-to-slack" ]]
}

@test "install:: copies source files to bin directory" {
	run_in_repo "$TEST_INSTALL_DIR"
	[[ "$status" -eq 0 ]]
	[[ -f "$TEST_INSTALL_DIR/bin/parse-payload.sh" ]]
	[[ -f "$TEST_INSTALL_DIR/bin/file-upload.sh" ]]
	[[ -f "$TEST_INSTALL_DIR/bin/resolve-mentions.sh" ]]
}

@test "install:: copies blocks directory" {
	run_in_repo "$TEST_INSTALL_DIR"
	[[ "$status" -eq 0 ]]
	[[ -d "$TEST_INSTALL_DIR/bin/blocks" ]]
	[[ -f "$TEST_INSTALL_DIR/bin/blocks/actions.sh" ]]
	[[ -f "$TEST_INSTALL_DIR/bin/blocks/rich-text.sh" ]]
}

@test "install:: sets execute permissions on all scripts" {
	run_in_repo "$TEST_INSTALL_DIR"
	[[ "$status" -eq 0 ]]
	[[ -x "$TEST_INSTALL_DIR/bin/parse-payload.sh" ]]
	[[ -x "$TEST_INSTALL_DIR/bin/blocks/actions.sh" ]]
}

@test "install:: outputs installation location" {
	run_in_repo "$TEST_INSTALL_DIR"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Installed send-to-slack to"
	echo "$output" | grep -q "$TEST_INSTALL_DIR/bin/send-to-slack"
}

@test "install:: handles prefix with trailing slash" {
	run_in_repo "$TEST_INSTALL_DIR/"
	[[ "$status" -eq 0 ]]
	[[ -f "$TEST_INSTALL_DIR/bin/send-to-slack" ]]
}

@test "install:: writes manifest with installed files" {
	run_in_repo "$TEST_INSTALL_DIR"
	[[ "$status" -eq 0 ]]
	local manifest
	manifest="$TEST_INSTALL_DIR/share/send-to-slack/install_manifest.txt"
	[[ -f "$manifest" ]]
	grep -q "$TEST_INSTALL_DIR/bin/send-to-slack" "$manifest"
	grep -q "$TEST_INSTALL_DIR/bin/parse-payload.sh" "$manifest"
	grep -q "$TEST_INSTALL_DIR/bin/blocks/actions.sh" "$manifest"
}

@test "install:: writes version file to share directory" {
	run_in_repo "$TEST_INSTALL_DIR"
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
	prefix=$(mktemp -d "${tmp_root}/install-tests.prefix.XXXXXX")
	run_in_repo "$prefix"
	[[ "$status" -eq 0 ]]
	[[ -x "$prefix/bin/send-to-slack" ]]
	[[ -f "$prefix/share/send-to-slack/install_manifest.txt" ]]
	rm -rf "$prefix"
}

@test "install:: outputs installation success message" {
	run_in_repo --local --path "$TEST_INSTALL_DIR"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Installed send-to-slack to"
}

@test "install:: outputs resolved reference" {
	run_in_repo --local --path "$TEST_INSTALL_DIR"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Resolved reference:"
}

@test "install:: --help shows usage information" {
	run "$SCRIPT" --help
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "usage:"
	echo "$output" | grep -Fq -- "--local"
	echo "$output" | grep -Fq -- "--commit"
	echo "$output" | grep -Fq -- "--path"
}

@test "install:: handles unknown options" {
	run env HOME="$TEMP_HOME" "$SCRIPT" --unknown-option
	[[ "$status" -ne 0 ]]
	echo "$output" | grep -q "unknown option"
}

@test "install:: checksum verification succeeds when checksum matches" {
	mock_network_tools
	run env HOME="$TEMP_HOME" "$SCRIPT" --commit "$FIXTURE_TAG" --path "$TEST_INSTALL_DIR"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Installed send-to-slack to"
}

@test "install:: auto-detects local mode when in git repository" {
	run_in_repo --path "$TEST_INSTALL_DIR"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Installed send-to-slack to"
	echo "$output" | grep -q "Resolved reference:"
}

@test "install:: auto-detects latest mode when not in git repository" {
	local tmp_root="${BATS_TEST_TMPDIR:-/tmp}"
	local non_git_dir
	local prefix
	non_git_dir=$(mktemp -d "${tmp_root}/install-tests.nongit.XXXXXX")
	prefix=$(mktemp -d "${tmp_root}/install-tests.prefix.XXXXXX")
	mock_network_tools
	run env HOME="$TEMP_HOME" bash -c "cd \"$non_git_dir\" && \"$SCRIPT\" --path \"$prefix\""
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Installed send-to-slack to"
	echo "$output" | grep -q "Resolved reference:"
	rm -rf "$non_git_dir" "$prefix"
}
