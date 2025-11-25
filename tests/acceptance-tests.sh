#!/usr/bin/env bats
#
# Consolidated acceptance tests for send-to-slack
#

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		echo "Failed to get git root" >&2
		exit 1
	fi

	SCRIPT="$GIT_ROOT/send-to-slack.sh"
	if [[ ! -f "$SCRIPT" ]]; then
		echo "Script not found: $SCRIPT" >&2
		exit 1
	fi

	if [[ -n "$SLACK_BOT_USER_OAUTH_TOKEN" ]]; then
		REAL_TOKEN="$SLACK_BOT_USER_OAUTH_TOKEN"
		export REAL_TOKEN
	fi

	export GIT_ROOT
	export SCRIPT
	export REAL_TOKEN

	return 0
}

setup() {
	source "$SCRIPT"

	SEND_TO_SLACK_ROOT="$GIT_ROOT"

	source "$SEND_TO_SLACK_ROOT/bin/parse-payload.sh"

	SLACK_BOT_USER_OAUTH_TOKEN="test-token"
	CHANNEL="#test"
	MESSAGE="test message"
	DRY_RUN="true"
	SHOW_METADATA="true"
	SHOW_PAYLOAD="true"
	BLOCKS="$(jq -n '[
		{
			"type": "section",
			"text": {
				"type": "plain_text",
				"text": "test message"
			}
		}
	]')"

	TEST_PAYLOAD_FILE=$(mktemp test-payload.XXXXXX)
	chmod 0600 "${TEST_PAYLOAD_FILE}"

	export SEND_TO_SLACK_ROOT
	export SLACK_BOT_USER_OAUTH_TOKEN
	export CHANNEL
	export MESSAGE
	export DRY_RUN
	export SHOW_METADATA
	export SHOW_PAYLOAD
	export TEST_PAYLOAD_FILE

	return 0
}

teardown() {
	[[ -n "$TEST_PAYLOAD_FILE" ]] && rm -f "$TEST_PAYLOAD_FILE"
	[[ -n "$ACCEPTANCE_TEST_FILE" ]] && rm -f "$ACCEPTANCE_TEST_FILE"
	[[ -n "$ACCEPTANCE_PAYLOAD_FILE" ]] && rm -f "$ACCEPTANCE_PAYLOAD_FILE"
	[[ -n "$parsed_payload_file" ]] && rm -f "$parsed_payload_file"
	return 0
}

########################################################
# Acceptance Tests
########################################################

@test "acceptance:: comprehensive message with all block types" {
	if [[ "$ACCEPTANCE_TEST" != "true" ]]; then
		skip "ACCEPTANCE_TEST is not set"
	fi

	if [[ -z "$REAL_TOKEN" ]]; then
		skip "REAL_TOKEN is required for acceptance tests"
	fi

	local token="$REAL_TOKEN"
	CHANNEL="notification-testing"
	DRY_RUN="false"

	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "acceptance") | .plan[0].params.blocks' "$GIT_ROOT/examples/acceptance.yaml")

	if ! echo "$blocks_json" | jq . >/dev/null 2>&1; then
		echo "Invalid blocks_json from acceptance.yaml" >&2
		echo "$blocks_json" >&2
		return 1
	fi

	ACCEPTANCE_TEST_FILE=$(mktemp test-upload.XXXXXX)
	echo "Test file content for upload testing" >"$ACCEPTANCE_TEST_FILE"

	local file_block
	file_block=$(jq -n --arg path "$ACCEPTANCE_TEST_FILE" '{ "file": { "path": $path } }')
	blocks_json=$(echo "$blocks_json" | jq --argjson file_block "$file_block" '. + [$file_block]')

	if ! echo "$blocks_json" | jq . >/dev/null 2>&1; then
		echo "Invalid blocks_json after adding file block" >&2
		echo "$blocks_json" >&2
		return 1
	fi

	jq -n \
		--arg token "$token" \
		--argjson blocks "$blocks_json" \
		--arg channel "$CHANNEL" \
		--arg dry_run "$DRY_RUN" \
		'{
			source: {
				slack_bot_user_oauth_token: $token
			},
			params: {
				channel: $channel,
				dry_run: $dry_run,
				blocks: $blocks
			}
		}' >"$TEST_PAYLOAD_FILE"

	if ! jq . "$TEST_PAYLOAD_FILE" >/dev/null 2>&1; then
		echo "Invalid JSON in test payload file" >&2
		cat "$TEST_PAYLOAD_FILE" >&2
		return 1
	fi

	export SEND_TO_SLACK_ROOT="$GIT_ROOT"
	run "$SCRIPT" <"$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "version"
	echo "$output" | grep -q "timestamp"
	echo "$output" | grep -q "main:: parsing payload"
	echo "$output" | grep -q "main:: creating Concourse metadata"
	echo "$output" | grep -q "main:: sending notification"
	echo "$output" | grep -q "main:: finished running send-to-slack.sh successfully"

	[[ -f "$ACCEPTANCE_TEST_FILE" ]] && rm -f "$ACCEPTANCE_TEST_FILE"
}

@test "acceptance:: params.raw" {
	if [[ "$ACCEPTANCE_TEST" != "true" ]]; then
		skip "ACCEPTANCE_TEST is not set"
	fi

	if [[ -z "$REAL_TOKEN" ]]; then
		skip "REAL_TOKEN is required for acceptance tests"
	fi

	local token="$REAL_TOKEN"
	CHANNEL="notification-testing"
	DRY_RUN="false"

	local raw_params
	raw_params=$(jq -n \
		--arg channel "$CHANNEL" \
		--arg dry_run "$DRY_RUN" \
		'{
			channel: $channel,
			dry_run: $dry_run,
			blocks: [
				{
					section: {
						type: "text",
						text: {
							type: "plain_text",
							text: "Acceptance test for params.raw"
						}
					}
				},
				{
					divider: {}
				},
				{
					actions: {
						elements: [
							{
								type: "button",
								text: {
									type: "plain_text",
									text: "Test Button"
								},
								action_id: "test_action"
							}
						]
					}
				},
				{
					context: {
						elements: [
							{
								type: "mrkdwn",
								text: "Testing raw parameter functionality"
							}
						]
					}
				}
			]
		}' | jq -c .)

	jq -n \
		--arg token "$token" \
		--arg raw "$raw_params" \
		'{
			source: {
				slack_bot_user_oauth_token: $token
			},
			params: {
				raw: $raw
			}
		}' >"$TEST_PAYLOAD_FILE"

	if ! jq . "$TEST_PAYLOAD_FILE" >/dev/null 2>&1; then
		echo "Invalid JSON in test payload file" >&2
		cat "$TEST_PAYLOAD_FILE" >&2
		return 1
	fi

	export SEND_TO_SLACK_ROOT="$GIT_ROOT"
	run "$SCRIPT" <"$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "version"
	echo "$output" | grep -q "timestamp"
	echo "$output" | grep -q "main:: parsing payload"
	echo "$output" | grep -q "using raw payload"
	echo "$output" | grep -q "main:: creating Concourse metadata"
	echo "$output" | grep -q "main:: sending notification"
	echo "$output" | grep -q "main:: finished running send-to-slack.sh successfully"
}

@test "acceptance:: params.from_file" {
	if [[ "$ACCEPTANCE_TEST" != "true" ]]; then
		skip "ACCEPTANCE_TEST is not set"
	fi

	if [[ -z "$REAL_TOKEN" ]]; then
		skip "REAL_TOKEN is required for acceptance tests"
	fi

	local token="$REAL_TOKEN"
	CHANNEL="notification-testing"
	DRY_RUN="false"

	ACCEPTANCE_PAYLOAD_FILE=$(mktemp acceptance-payload.XXXXXX)
	jq -n \
		--arg channel "$CHANNEL" \
		--arg dry_run "$DRY_RUN" \
		'{
			channel: $channel,
			dry_run: $dry_run,
			blocks: [
				{
					header: {
						text: {
							type: "plain_text",
							text: "Acceptance Test"
						}
					}
				},
				{
					section: {
						type: "text",
						text: {
							type: "mrkdwn",
							text: "Testing *params.from_file* functionality"
						}
					}
				},
				{
					context: {
						elements: [
							{
								type: "plain_text",
								text: "File-based payload processing"
							}
						]
					}
				}
			]
		}' >"$ACCEPTANCE_PAYLOAD_FILE"

	jq -n \
		--arg file "$ACCEPTANCE_PAYLOAD_FILE" \
		--arg token "$token" \
		'{
			source: {
				slack_bot_user_oauth_token: $token
			},
			params: {
				from_file: $file
			}
		}' >"$TEST_PAYLOAD_FILE"

	if ! jq . "$TEST_PAYLOAD_FILE" >/dev/null 2>&1; then
		echo "Invalid JSON in test payload file" >&2
		cat "$TEST_PAYLOAD_FILE" >&2
		return 1
	fi

	export SEND_TO_SLACK_ROOT="$GIT_ROOT"
	run "$SCRIPT" <"$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "version"
	echo "$output" | grep -q "timestamp"
	echo "$output" | grep -q "main:: parsing payload"
	echo "$output" | grep -q "using payload from file"
	echo "$output" | grep -q "main:: creating Concourse metadata"
	echo "$output" | grep -q "main:: sending notification"
	echo "$output" | grep -q "main:: finished running send-to-slack.sh successfully"

	[[ -f "$ACCEPTANCE_PAYLOAD_FILE" ]] && rm -f "$ACCEPTANCE_PAYLOAD_FILE"
}

@test "acceptance:: crosspost" {
	if [[ "$ACCEPTANCE_TEST" != "true" ]]; then
		skip "ACCEPTANCE_TEST is not set"
	fi

	if [[ -z "$REAL_TOKEN" ]]; then
		skip "REAL_TOKEN is required for acceptance tests"
	fi

	local token="$REAL_TOKEN"
	CHANNEL="notification-testing"
	DRY_RUN="false"

	jq -n \
		--arg token "$token" \
		--arg channel "$CHANNEL" \
		--arg dry_run "$DRY_RUN" \
		'{
			source: {
				slack_bot_user_oauth_token: $token
			},
			params: {
				channel: $channel,
				dry_run: $dry_run,
				blocks: [
					{
						section: {
							type: "text",
							text: {
								type: "plain_text",
								text: "Smoke test for crossposting functionality"
							}
						}
					}
				],
				crosspost: {
					channels: ["side-channel"],
					text: "See the original message"
				}
			}
		}' >"$TEST_PAYLOAD_FILE"

	if ! jq . "$TEST_PAYLOAD_FILE" >/dev/null 2>&1; then
		echo "Invalid JSON in test payload file" >&2
		cat "$TEST_PAYLOAD_FILE" >&2
		return 1
	fi

	export SEND_TO_SLACK_ROOT="$GIT_ROOT"
	run "$SCRIPT" <"$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "version"
	echo "$output" | grep -q "timestamp"
	echo "$output" | grep -q "main:: parsing payload"
	echo "$output" | grep -q "main:: creating Concourse metadata"
	echo "$output" | grep -q "main:: sending notification"
	echo "$output" | grep -q "main:: finished running send-to-slack.sh successfully"

	local send_count
	send_count=$(echo "$output" | grep -c "send_notification:: message delivered to Slack successfully" || echo "0")
	[[ "$send_count" -ge 2 ]]
}

@test "acceptance:: thread reply with thread_ts" {
	if [[ "$ACCEPTANCE_TEST" != "true" ]]; then
		skip "ACCEPTANCE_TEST is not set"
	fi

	if [[ -z "$REAL_TOKEN" ]]; then
		skip "REAL_TOKEN is required for acceptance tests"
	fi

	local token="$REAL_TOKEN"
	CHANNEL="threads"
	DRY_RUN="false"

	local permalink_ts="1763161862880069"
	local thread_ts="${permalink_ts:0:10}.${permalink_ts:10}"

	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "acceptance") | .plan[0].params.blocks' "$GIT_ROOT/examples/acceptance.yaml")

	if ! echo "$blocks_json" | jq . >/dev/null 2>&1; then
		echo "Invalid blocks_json from acceptance.yaml" >&2
		echo "$blocks_json" >&2
		return 1
	fi

	ACCEPTANCE_TEST_FILE=$(mktemp test-upload.XXXXXX)
	echo "Test file content for upload testing" >"$ACCEPTANCE_TEST_FILE"

	local file_block
	file_block=$(jq -n --arg path "$ACCEPTANCE_TEST_FILE" '{ "file": { "path": $path } }')
	blocks_json=$(echo "$blocks_json" | jq --argjson file_block "$file_block" '. + [$file_block]')

	if ! echo "$blocks_json" | jq . >/dev/null 2>&1; then
		echo "Invalid blocks_json after adding file block" >&2
		echo "$blocks_json" >&2
		return 1
	fi

	jq -n \
		--arg token "$token" \
		--argjson blocks "$blocks_json" \
		--arg channel "$CHANNEL" \
		--arg dry_run "$DRY_RUN" \
		--arg thread_ts "$thread_ts" \
		'{
			source: {
				slack_bot_user_oauth_token: $token
			},
			params: {
				channel: $channel,
				dry_run: $dry_run,
				thread_ts: $thread_ts,
				blocks: $blocks
			}
		}' >"$TEST_PAYLOAD_FILE"

	if ! jq . "$TEST_PAYLOAD_FILE" >/dev/null 2>&1; then
		echo "Invalid JSON in test payload file" >&2
		cat "$TEST_PAYLOAD_FILE" >&2
		return 1
	fi

	export SEND_TO_SLACK_ROOT="$GIT_ROOT"
	run "$SCRIPT" <"$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "version"
	echo "$output" | grep -q "timestamp"
	echo "$output" | grep -q "main:: parsing payload"
	echo "$output" | grep -q "main:: creating Concourse metadata"
	echo "$output" | grep -q "main:: sending notification"

	local parsed_payload_file
	parsed_payload_file=$(mktemp parsed-payload.XXXXXX)
	trap "rm -f '$parsed_payload_file' 2>/dev/null || true" EXIT
	if ! parse_payload "$TEST_PAYLOAD_FILE" >"$parsed_payload_file"; then
		echo "parse_payload failed" >&2
		rm -f "$parsed_payload_file"
		trap - EXIT
		return 1
	fi

	local parsed_payload
	parsed_payload=$(cat "$parsed_payload_file")
	rm -f "$parsed_payload_file"
	trap - EXIT

	echo "$parsed_payload" | jq -e --arg thread_ts "$thread_ts" '.thread_ts == $thread_ts' >/dev/null
	echo "$output" | grep -q "main:: finished running send-to-slack.sh successfully"

	[[ -f "$ACCEPTANCE_TEST_FILE" ]] && rm -f "$ACCEPTANCE_TEST_FILE"
}

@test "acceptance:: create_thread" {
	if [[ "$ACCEPTANCE_TEST" != "true" ]]; then
		skip "ACCEPTANCE_TEST is not set"
	fi

	if [[ -z "$REAL_TOKEN" ]]; then
		skip "REAL_TOKEN is required for acceptance tests"
	fi

	local token="$REAL_TOKEN"
	CHANNEL="notification-testing"
	DRY_RUN="false"

	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "acceptance") | .plan[0].params.blocks' "$GIT_ROOT/examples/acceptance.yaml")

	if ! echo "$blocks_json" | jq . >/dev/null 2>&1; then
		echo "Invalid blocks_json from acceptance.yaml" >&2
		echo "$blocks_json" >&2
		return 1
	fi

	ACCEPTANCE_TEST_FILE=$(mktemp test-upload.XXXXXX)
	echo "Test file content for upload testing" >"$ACCEPTANCE_TEST_FILE"

	local file_block
	file_block=$(jq -n --arg path "$ACCEPTANCE_TEST_FILE" '{ "file": { "path": $path } }')
	blocks_json=$(echo "$blocks_json" | jq --argjson file_block "$file_block" '. + [$file_block]')

	if ! echo "$blocks_json" | jq . >/dev/null 2>&1; then
		echo "Invalid blocks_json after adding file block" >&2
		echo "$blocks_json" >&2
		return 1
	fi

	jq -n \
		--arg token "$token" \
		--argjson blocks "$blocks_json" \
		--arg channel "$CHANNEL" \
		--arg dry_run "$DRY_RUN" \
		'{
			source: {
				slack_bot_user_oauth_token: $token
			},
			params: {
				channel: $channel,
				dry_run: $dry_run,
				create_thread: true,
				blocks: $blocks
			}
		}' >"$TEST_PAYLOAD_FILE"

	if ! jq . "$TEST_PAYLOAD_FILE" >/dev/null 2>&1; then
		echo "Invalid JSON in test payload file" >&2
		cat "$TEST_PAYLOAD_FILE" >&2
		return 1
	fi

	export SEND_TO_SLACK_ROOT="$GIT_ROOT"
	run "$SCRIPT" <"$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "version"
	echo "$output" | grep -q "timestamp"
	echo "$output" | grep -q "main:: parsing payload"
	echo "$output" | grep -q "main:: creating Concourse metadata"
	echo "$output" | grep -q "main:: sending notification"
	echo "$output" | grep -q "main:: finished running send-to-slack.sh successfully"

	[[ -f "$ACCEPTANCE_TEST_FILE" ]] && rm -f "$ACCEPTANCE_TEST_FILE"
}

@test "acceptance:: actions block button sends hello world to channel" {
	if [[ "$ACCEPTANCE_TEST" != "true" ]]; then
		skip "ACCEPTANCE_TEST is not set"
	fi

	if [[ -z "$REAL_TOKEN" ]]; then
		skip "REAL_TOKEN is required for acceptance tests"
	fi

	local token="$REAL_TOKEN"
	CHANNEL="notification-testing"
	DRY_RUN="false"

	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "actions-button-channel") | .plan[0].params.blocks' "$GIT_ROOT/examples/actions.yaml")

	if ! echo "$blocks_json" | jq . >/dev/null 2>&1; then
		echo "Invalid blocks_json from actions.yaml" >&2
		echo "$blocks_json" >&2
		return 1
	fi

	jq -n \
		--arg token "$token" \
		--argjson blocks "$blocks_json" \
		--arg channel "$CHANNEL" \
		--arg dry_run "$DRY_RUN" \
		'{
			source: {
				slack_bot_user_oauth_token: $token
			},
			params: {
				channel: $channel,
				dry_run: $dry_run,
				blocks: $blocks
			}
		}' >"$TEST_PAYLOAD_FILE"

	if ! jq . "$TEST_PAYLOAD_FILE" >/dev/null 2>&1; then
		echo "Invalid JSON in test payload file" >&2
		cat "$TEST_PAYLOAD_FILE" >&2
		return 1
	fi

	export SEND_TO_SLACK_ROOT="$GIT_ROOT"
	run "$SCRIPT" <"$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "version"
	echo "$output" | grep -q "timestamp"
	echo "$output" | grep -q "main:: parsing payload"
	echo "$output" | grep -q "main:: creating Concourse metadata"
	echo "$output" | grep -q "main:: sending notification"
	echo "$output" | grep -q "main:: finished running send-to-slack.sh successfully"

	echo ""
	echo "=========================================="
	echo "Acceptance Test: Channel Message Button"
	echo "=========================================="
	echo "1. Check Slack channel: ${CHANNEL}"
	echo "2. Click the 'Send to Channel' button"
	echo "3. Verify 'Hello, world!' message appears in the same channel"
	echo "=========================================="
}

@test "acceptance:: actions block button sends hello world to user" {
	if [[ "$ACCEPTANCE_TEST" != "true" ]]; then
		skip "ACCEPTANCE_TEST is not set"
	fi

	if [[ -z "$REAL_TOKEN" ]]; then
		skip "REAL_TOKEN is required for acceptance tests"
	fi

	local token="$REAL_TOKEN"
	CHANNEL="notification-testing"
	DRY_RUN="false"

	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "actions-button-user") | .plan[0].params.blocks' "$GIT_ROOT/examples/actions.yaml")

	if ! echo "$blocks_json" | jq . >/dev/null 2>&1; then
		echo "Invalid blocks_json from actions.yaml" >&2
		echo "$blocks_json" >&2
		return 1
	fi

	jq -n \
		--arg token "$token" \
		--argjson blocks "$blocks_json" \
		--arg channel "$CHANNEL" \
		--arg dry_run "$DRY_RUN" \
		'{
			source: {
				slack_bot_user_oauth_token: $token
			},
			params: {
				channel: $channel,
				dry_run: $dry_run,
				blocks: $blocks
			}
		}' >"$TEST_PAYLOAD_FILE"

	if ! jq . "$TEST_PAYLOAD_FILE" >/dev/null 2>&1; then
		echo "Invalid JSON in test payload file" >&2
		cat "$TEST_PAYLOAD_FILE" >&2
		return 1
	fi

	export SEND_TO_SLACK_ROOT="$GIT_ROOT"
	run "$SCRIPT" <"$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "version"
	echo "$output" | grep -q "timestamp"
	echo "$output" | grep -q "main:: parsing payload"
	echo "$output" | grep -q "main:: creating Concourse metadata"
	echo "$output" | grep -q "main:: sending notification"
	echo "$output" | grep -q "main:: finished running send-to-slack.sh successfully"

	echo ""
	echo "=========================================="
	echo "Acceptance Test: User DM Button"
	echo "=========================================="
	echo "1. Check Slack channel: ${CHANNEL}"
	echo "2. Click the 'Send to Me' button"
	echo "3. Verify 'Hello, world!' message appears in your DMs"
	echo "=========================================="
}

@test "acceptance:: slack-native format with all block types" {
	if [[ "$ACCEPTANCE_TEST" != "true" ]]; then
		skip "ACCEPTANCE_TEST is not set"
	fi

	if [[ -z "$REAL_TOKEN" ]]; then
		skip "REAL_TOKEN is required for acceptance tests"
	fi

	local token="$REAL_TOKEN"
	CHANNEL="notification-testing"
	DRY_RUN="false"

	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "slack-native-format-all-block-types") | .plan[0].params.blocks' "$GIT_ROOT/examples/slack-native.yaml")

	if ! echo "$blocks_json" | jq . >/dev/null 2>&1; then
		echo "Invalid blocks_json from slack-native.yaml" >&2
		echo "$blocks_json" >&2
		return 1
	fi

	jq -n \
		--arg token "$token" \
		--argjson blocks "$blocks_json" \
		--arg channel "$CHANNEL" \
		--arg dry_run "$DRY_RUN" \
		'{
			source: {
				slack_bot_user_oauth_token: $token
			},
			params: {
				channel: $channel,
				dry_run: $dry_run,
				blocks: $blocks
			}
		}' >"$TEST_PAYLOAD_FILE"

	if ! jq . "$TEST_PAYLOAD_FILE" >/dev/null 2>&1; then
		echo "Invalid JSON in test payload file" >&2
		cat "$TEST_PAYLOAD_FILE" >&2
		return 1
	fi

	export SEND_TO_SLACK_ROOT="$GIT_ROOT"
	run "$SCRIPT" <"$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "version"
	echo "$output" | grep -q "timestamp"
	echo "$output" | grep -q "main:: parsing payload"
	echo "$output" | grep -q "main:: creating Concourse metadata"
	echo "$output" | grep -q "main:: sending notification"
	echo "$output" | grep -q "main:: finished running send-to-slack.sh successfully"

	echo ""
	echo "=========================================="
	echo "Acceptance Test: Slack Native Format"
	echo "=========================================="
	echo "1. Check Slack channel: ${CHANNEL}"
	echo "2. Verify all block types are displayed correctly:"
	echo "   - Header block"
	echo "   - Divider blocks"
	echo "   - Section blocks (text and fields)"
	echo "   - Context block"
	echo "   - Markdown block"
	echo "   - Rich text block"
	echo "   - Image block"
	echo "   - Video block"
	echo "   - Actions block"
	echo "   - Table block (in attachment)"
	echo "   - Colored blocks (in attachments)"
	echo "=========================================="
}
