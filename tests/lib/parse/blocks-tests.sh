#!/usr/bin/env bats
#
# Test suite for parse/blocks.sh
#

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		fail "Failed to get git root"
	fi

	BLOCKS_SCRIPT="$GIT_ROOT/lib/parse/blocks.sh"
	PAYLOAD_SCRIPT="$GIT_ROOT/lib/parse/payload.sh"
	if [[ ! -f "$BLOCKS_SCRIPT" ]]; then
		fail "Script not found: $BLOCKS_SCRIPT"
	fi
	if [[ ! -f "$PAYLOAD_SCRIPT" ]]; then
		fail "Script not found: $PAYLOAD_SCRIPT"
	fi

	export GIT_ROOT
	export BLOCKS_SCRIPT
	export PAYLOAD_SCRIPT

	return 0
}

setup() {
	SEND_TO_SLACK_ROOT="$GIT_ROOT"
	export SEND_TO_SLACK_ROOT

	_SLACK_WORKSPACE=$(mktemp -d "${BATS_TEST_TMPDIR}/parse-blocks-tests.workspace.XXXXXX")
	export _SLACK_WORKSPACE

	source "$PAYLOAD_SCRIPT"
	source "$BLOCKS_SCRIPT"

	CHANNEL="C123TEST"
	DELIVERY_METHOD="api"
	export CHANNEL
	export DELIVERY_METHOD

	INPUT_PAYLOAD=$(mktemp "${BATS_TEST_TMPDIR}/parse-blocks-tests.input.XXXXXX")
	export INPUT_PAYLOAD

	return 0
}

teardown() {
	rm -rf "$_SLACK_WORKSPACE"
	rm -f "$INPUT_PAYLOAD"

	return 0
}

@test "_process_blocks_append_block:: returns error for invalid JSON input" {
	run _process_blocks_append_block "{"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"_process_blocks_append_block:: block_item must be valid JSON"* ]]
}

@test "process_blocks:: returns error when append operation fails" {
	BLOCKS_FILE="${BATS_TEST_TMPDIR}/parse-blocks-tests.blocks-dir"
	mkdir -p "$BLOCKS_FILE"
	ATTACHMENTS_FILE=$(mktemp "${BATS_TEST_TMPDIR}/parse-blocks-tests.attachments.XXXXXX")
	echo '[]' >"$ATTACHMENTS_FILE"

	run _process_blocks_append_block '{"section":{"type":"text","text":{"type":"plain_text","text":"Append failure test"}}}'
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"_process_blocks_append_block:: failed to append block to blocks"* ]]
}
