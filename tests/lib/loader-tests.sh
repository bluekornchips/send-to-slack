#!/usr/bin/env bats
#
# Tests for lib/loader.sh
#

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		fail "Failed to get git root"
	fi

	LIB="$GIT_ROOT/lib/loader.sh"
	if [[ ! -f "$LIB" ]]; then
		fail "Script not found: $LIB"
	fi

	export GIT_ROOT
	export LIB

	return 0
}

setup() {
	# shellcheck source=lib/loader.sh
	source "$LIB"
	export -f source_required _load_libs find_root_dir initialize_script_environment
}

@test "SEND_TO_SLACK_LIB_MANIFEST:: includes loader dependencies in order" {
	[[ "${#SEND_TO_SLACK_LIB_MANIFEST[@]}" -gt 0 ]]
	[[ "${SEND_TO_SLACK_LIB_MANIFEST[0]}" == "get-version.sh" ]]
	[[ "${SEND_TO_SLACK_LIB_MANIFEST[-1]}" == "parse/blocks.sh" ]]
}

@test "source_required:: propagates source failures" {
	local bad_module
	bad_module=$(mktemp "${BATS_TEST_TMPDIR}/loader-bad-module.XXXXXX")
	printf '#!/usr/bin/env bash\nreturn 1\n' >"$bad_module"

	run source_required "$bad_module"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "failed to source"

	rm -f "$bad_module"
}

@test "_load_libs:: loads the complete manifest from the repository" {
	SEND_TO_SLACK_ROOT="$GIT_ROOT"
	export SEND_TO_SLACK_ROOT

	if ! _load_libs "$GIT_ROOT"; then
		return 1
	fi

	declare -f parse_main_args >/dev/null
	declare -f run_delivery_from_input >/dev/null
	declare -f send_notification >/dev/null
}
