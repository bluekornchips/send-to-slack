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
	if [[ ! -f "$SCRIPT" ]]; then
		fail "Script not found: $SCRIPT"
	fi
	if [[ ! -f "$PARSE_BLOCKS_SH" ]]; then
		fail "Script not found: $PARSE_BLOCKS_SH"
	fi

	if [[ -n "$SLACK_BOT_USER_OAUTH_TOKEN" ]]; then
		REAL_TOKEN="$SLACK_BOT_USER_OAUTH_TOKEN"
		export REAL_TOKEN
	fi

	RICH_TEXT_EXAMPLES_FILE="$GIT_ROOT/examples/rich-text.yaml"
	BLOCK_FIXTURES_DIR="$GIT_ROOT/examples/fixtures"

	export GIT_ROOT
	export SCRIPT
	export PARSE_BLOCKS_SH
	export RICH_TEXT_EXAMPLES_FILE
	export BLOCK_FIXTURES_DIR

	return 0
}

payload_tests_setup() {
	source "$SCRIPT"
	source "$PARSE_BLOCKS_SH"

	_SLACK_WORKSPACE=$(mktemp -d "${BATS_TEST_TMPDIR}/payload-tests.workspace.XXXXXX")
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
	[[ -n "${invalid_file:-}" ]] && rm -f "$invalid_file"
	[[ -n "${output_file:-}" ]] && rm -f "$output_file"
	[[ -n "${payload_file:-}" ]] && rm -f "$payload_file"
	return 0
}

create_test_payload() {
	local blocks_json='[]'

	# Optional YAML/JSON in BLOCKS for fixtures that still set it.
	if [[ -n "${BLOCKS:-}" ]]; then
		if ! blocks_json=$(yq -o json <<<"$BLOCKS"); then
			echo "create_test_payload:: failed to convert BLOCKS with yq" >&2
			return 1
		fi
	fi

	jq -n \
		--argjson blocks "$blocks_json" \
		--arg channel "$CHANNEL" \
		--arg dry_run "$DRY_RUN" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				channel: $channel,
				blocks: $blocks,
				dry_run: true
			}
		}' >"$TEST_PAYLOAD_FILE"
}

# Read block JSON from the CREATE_BLOCK_OUTPUT_FILE written by create_block
block_output_json() { cat "$CREATE_BLOCK_OUTPUT_FILE"; }
