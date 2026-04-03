#!/usr/bin/env bats
#
# Tests for lib/metadata.sh
#

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		fail "Failed to get git root"
	fi

	SCRIPT="$GIT_ROOT/lib/metadata.sh"
	if [[ ! -f "$SCRIPT" ]]; then
		fail "Script not found: $SCRIPT"
	fi

	export GIT_ROOT
	export SCRIPT

	return 0
}

setup() {
	source "$SCRIPT"

	DRY_RUN="true"
	SHOW_METADATA="true"
	SHOW_PAYLOAD="true"

	export DRY_RUN
	export SHOW_METADATA
	export SHOW_PAYLOAD

	return 0
}

########################################################
# create_metadata
########################################################

@test "create_metadata:: creates metadata when show_metadata is true" {
	SHOW_METADATA="true"
	DRY_RUN="true"
	SHOW_PAYLOAD="false"
	export SHOW_METADATA
	export DRY_RUN
	export SHOW_PAYLOAD
	local payload='{"channel": "#test", "text": "test"}'

	create_metadata "$payload"
	[[ -n "$METADATA" ]]
	echo "$METADATA" | jq -e '.[] | select(.name == "dry_run") | .value == "true"' >/dev/null
}

@test "create_metadata:: includes payload when show_payload is true" {
	SHOW_METADATA="true"
	DRY_RUN="false"
	SHOW_PAYLOAD="true"
	export SHOW_METADATA
	export DRY_RUN
	export SHOW_PAYLOAD
	local payload='{"channel": "#test", "text": "test"}'

	create_metadata "$payload"
	[[ -n "$METADATA" ]]
	echo "$METADATA" | jq -e '.[] | select(.name == "payload")' >/dev/null
}

@test "create_metadata:: does nothing when show_metadata is false" {
	SHOW_METADATA="false"
	export SHOW_METADATA
	local payload='{"channel": "#test", "text": "test"}'

	create_metadata "$payload"
	[[ "$METADATA" == "[]" ]]
}

@test "create_metadata:: non-UTF payload produces valid metadata" {
	SHOW_METADATA="true"
	SHOW_PAYLOAD="true"
	export SHOW_METADATA
	export SHOW_PAYLOAD
	local bad_payload
	bad_payload=$(printf '{"channel":"#test","text":"\200"}')

	run create_metadata "$bad_payload"
	[[ "$status" -eq 0 ]]
	echo "$METADATA" | jq -e '.' >/dev/null
}

@test "create_metadata:: oversize payload strips blocks and attachments" {
	SHOW_METADATA="true"
	SHOW_PAYLOAD="true"
	export SHOW_METADATA
	export SHOW_PAYLOAD
	local safe_size
	local huge_payload
	safe_size=$(($(getconf ARG_MAX 2>/dev/null || echo 262144) / 4))
	local big_text_file
	big_text_file=$(mktemp)
	head -c "$((safe_size + 1024))" /dev/zero | tr '\0' 'A' >"$big_text_file"
	huge_payload=$(jq -n \
		--rawfile big_text "$big_text_file" \
		'{"channel":"#test","blocks":[{"type":"section","text":{"type":"mrkdwn","text":$big_text}}],"attachments":[{"text":"attach"}]}')
	rm -f "$big_text_file"

	create_metadata "$huge_payload"
	echo "$METADATA" | jq -e '.' >/dev/null
	echo "$METADATA" | jq -e '.[] | select(.name == "payload") | .value | fromjson | has("blocks") | not' >/dev/null
	echo "$METADATA" | jq -e '.[] | select(.name == "payload") | .value | fromjson | has("attachments") | not' >/dev/null
	echo "$METADATA" | jq -e '.[] | select(.name == "payload_note")' >/dev/null
	[[ ${#METADATA} -le "$safe_size" ]]
}

@test "create_metadata:: normal-sized payload with blocks preserves blocks in metadata" {
	SHOW_METADATA="true"
	SHOW_PAYLOAD="true"
	export SHOW_METADATA
	export SHOW_PAYLOAD
	local payload
	payload='{"channel":"#test","blocks":[{"type":"section","text":{"type":"mrkdwn","text":"hello"}}]}'

	create_metadata "$payload"
	echo "$METADATA" | jq -e '.[] | select(.name == "payload") | .value | fromjson | .blocks | length > 0' >/dev/null
	echo "$METADATA" | jq -e '[.[] | .name] | contains(["payload_note"]) | not' >/dev/null
}
