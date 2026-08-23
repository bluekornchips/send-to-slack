#!/usr/bin/env bats
#
# Tests for lib/slack/api.sh
#

load "api/api-test-helper.sh"

setup_file() {
	api_test_setup_file
	return 0
}

setup() {
	api_test_setup
	return 0
}

teardown() {
	api_test_teardown
	return 0
}

@test "api.sh:: loads all Slack API modules" {
	declare -f send_notification >/dev/null
	declare -f update_message >/dev/null
	declare -f get_message_permalink >/dev/null
	declare -f _parse_curl_http_response >/dev/null
}

@test "source_required:: fails on missing module" {
	run source_required "/tmp/does-not-exist-$(date +%s).sh"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "missing module"
}

@test "_load_libs:: fails when manifest module is missing" {
	local bad_root
	bad_root=$(mktemp -d "${BATS_TEST_TMPDIR}/bad-lib-root.XXXXXX")
	mkdir -p "${bad_root}/lib/parse"
	cp "${GIT_ROOT}/lib/parse/payload.sh" "${bad_root}/lib/parse/payload.sh"
	run _load_libs "$bad_root"
	[[ "$status" -eq 1 ]]
	rm -rf "$bad_root"
}

@test "_load_libs:: fails when sourced module returns nonzero" {
	local bad_root
	bad_root=$(mktemp -d "${BATS_TEST_TMPDIR}/bad-lib-root2.XXXXXX")
	mkdir -p "${bad_root}/lib"
	printf '#!/usr/bin/env bash\nreturn 1\n' >"${bad_root}/lib/get-version.sh"
	for rel in "${SEND_TO_SLACK_LIB_MANIFEST[@]}"; do
		mkdir -p "${bad_root}/lib/$(dirname "$rel")"
		if [[ ! -f "${bad_root}/lib/${rel}" ]]; then
			printf '#!/usr/bin/env bash\n' >"${bad_root}/lib/${rel}"
		fi
	done
	run _load_libs "$bad_root"
	[[ "$status" -eq 1 ]]
	rm -rf "$bad_root"
}
