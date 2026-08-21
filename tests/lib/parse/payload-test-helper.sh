#!/usr/bin/env bash
#
# Shared setup and helpers for payload parse bats tests.
#

payload_tests_setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		fail "Failed to get git root"
	fi

	SCRIPT="$GIT_ROOT/lib/parse/payload.sh"
	PARSE_BLOCKS_SH="$GIT_ROOT/lib/parse/blocks.sh"
	BLOCK_FIXTURES_DIR="$GIT_ROOT/examples/fixtures"
	if [[ ! -f "$SCRIPT" ]]; then
		fail "Script not found: $SCRIPT"
	fi
	if [[ ! -f "$PARSE_BLOCKS_SH" ]]; then
		fail "Script not found: $PARSE_BLOCKS_SH"
	fi

	export GIT_ROOT
	export SCRIPT
	export PARSE_BLOCKS_SH
	export BLOCK_FIXTURES_DIR

	return 0
}

payload_tests_setup() {
	source "$SCRIPT"
	source "$PARSE_BLOCKS_SH"

	_SLACK_WORKSPACE=$(mktemp -d "${BATS_TEST_TMPDIR}/payload-core.workspace.XXXXXX")
	export _SLACK_WORKSPACE

	TEST_PAYLOAD_FILE=$(mktemp "$_SLACK_WORKSPACE/test-payload.XXXXXX")
	export TEST_PAYLOAD_FILE
	create_test_payload

	CREATE_BLOCK_OUTPUT_FILE=$(mktemp "$_SLACK_WORKSPACE/block-out.XXXXXX")
	export CREATE_BLOCK_OUTPUT_FILE

	SLACK_BOT_USER_OAUTH_TOKEN="xoxb-test-token"
	CHANNEL="main"
	DRY_RUN="true"

	export SLACK_BOT_USER_OAUTH_TOKEN
	export CHANNEL
	export DRY_RUN

	return 0
}

payload_tests_teardown() {
	rm -rf "$_SLACK_WORKSPACE"
	return 0
}

create_test_payload() {
	jq -n \
		--arg channel "$CHANNEL" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				blocks: [],
				dry_run: true
			}
		}' >"$TEST_PAYLOAD_FILE"
}
