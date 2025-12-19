#!/usr/bin/env bats
#
# Tests for ci/build.sh helper functions
#

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		fail "setup_file:: git root not found"
	fi

	BUILD_SCRIPT="${GIT_ROOT}/ci/build.sh"
	if [[ ! -f "$BUILD_SCRIPT" ]]; then
		fail "setup_file:: build script missing: $BUILD_SCRIPT"
	fi

	ORIGINAL_GIT_ROOT="$GIT_ROOT"
	VERSION_VALUE="$(tr -d '\r\n' <"${ORIGINAL_GIT_ROOT}/VERSION")"

	export BUILD_SCRIPT
	export ORIGINAL_GIT_ROOT
	export VERSION_VALUE
}

setup() {
	OUTPUT_DIR="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/send-to-slack-build.XXXXXX")"
	GIT_ROOT="$ORIGINAL_GIT_ROOT"

	export OUTPUT_DIR
	export GIT_ROOT

	local old_e
	local old_pipefail
	old_e="$(set +o | grep 'set -e' || true)"
	old_pipefail="$(set +o | grep 'pipefail' || true)"
	set +e +o pipefail
	# shellcheck source=/dev/null
	source "$BUILD_SCRIPT" || true
	eval "$old_e" || true
	eval "$old_pipefail" || true
	set +e +o pipefail
}

teardown() {
	if [[ -n "$OUTPUT_DIR" && -d "$OUTPUT_DIR" ]]; then
		rm -rf "$OUTPUT_DIR"
	fi

	GIT_ROOT="$ORIGINAL_GIT_ROOT"
}

@test "build.sh:: resolve_version prefers provided value" {
	run resolve_version "v2.3.4"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "v2.3.4" ]]
}

@test "build.sh:: resolve_version falls back to VERSION file" {
	run resolve_version ""
	[[ "$status" -eq 0 ]]
	[[ "$output" == "$VERSION_VALUE" ]]
}

@test "build.sh:: resolve_version errors without input or VERSION" {
	local temp_root
	temp_root="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/send-to-slack-empty.XXXXXX")"

	GIT_ROOT="$temp_root"
	run resolve_version ""
	[[ "$status" -ne 0 ]]
	echo "$output" | grep -qi "unable to determine version"

	rm -rf "$temp_root"
}

@test "build.sh:: build_tarball produces linux and darwin archives" {
	local version_clean
	local tarball_path

	version_clean="${VERSION_VALUE#v}"

	run build_tarball "$VERSION_VALUE" "$OUTPUT_DIR"
	[[ "$status" -eq 0 ]]

	for platform in "linux_amd64" "darwin_amd64"; do
		tarball_path="${OUTPUT_DIR}/send-to-slack_${version_clean}_${platform}.tar.gz"

		[[ -f "$tarball_path" ]]
		tar -tzf "$tarball_path" | grep -q "^send-to-slack$"
		tar -tzf "$tarball_path" | grep -q "^VERSION$"
		tar -xzOf "$tarball_path" VERSION | grep -qx "$VERSION_VALUE"
	done
}

@test "build.sh:: parse_args accepts all as dockerfile choice" {
	DOCKERFILE_CHOICE=""
	run parse_args --dockerfile all
	[[ "$status" -eq 0 ]]
	[[ "$DOCKERFILE_CHOICE" == "all" ]]
}

@test "build.sh:: parse_args accepts concourse as dockerfile choice" {
	DOCKERFILE_CHOICE=""
	run parse_args --dockerfile concourse
	[[ "$status" -eq 0 ]]
	[[ "$DOCKERFILE_CHOICE" == "concourse" ]]
}

@test "build.sh:: parse_args accepts test as dockerfile choice" {
	DOCKERFILE_CHOICE=""
	run parse_args --dockerfile test
	[[ "$status" -eq 0 ]]
	[[ "$DOCKERFILE_CHOICE" == "test" ]]
}

@test "build.sh:: parse_args accepts remote as dockerfile choice" {
	DOCKERFILE_CHOICE=""
	run parse_args --dockerfile remote
	[[ "$status" -eq 0 ]]
	[[ "$DOCKERFILE_CHOICE" == "remote" ]]
}

@test "build.sh:: parse_args rejects invalid dockerfile choice" {
	DOCKERFILE_CHOICE=""
	run parse_args --dockerfile invalid
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "invalid dockerfile choice"
	echo "$output" | grep -q "allowed: concourse|test|remote|all"
}

@test "build.sh:: parse_args requires argument for --dockerfile" {
	DOCKERFILE_CHOICE=""
	run parse_args --dockerfile
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "option --dockerfile requires an argument"
}
