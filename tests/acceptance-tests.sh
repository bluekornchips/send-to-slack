#!/usr/bin/env bats
#
# Consolidated acceptance tests for send-to-slack
#

RUN_ACCEPTANCE_TEST=${RUN_ACCEPTANCE_TEST:-false}

setup_file() {
	[[ "$RUN_ACCEPTANCE_TEST" != "true" ]] && skip "RUN_ACCEPTANCE_TEST is not set"

	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		fail "Failed to get git root"
	fi

	SCRIPT="$GIT_ROOT/bin/send-to-slack.sh"
	if [[ ! -f "$SCRIPT" ]]; then
		fail "Script not found: $SCRIPT"
	fi

	if [[ -z "$CHANNEL" ]]; then
		fail "CHANNEL environment variable is not set"
	fi

	if [[ -n "$SLACK_BOT_USER_OAUTH_TOKEN" ]]; then
		REAL_TOKEN="$SLACK_BOT_USER_OAUTH_TOKEN"
		export REAL_TOKEN
	fi

	if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
		REAL_WEBHOOK_URL="$SLACK_WEBHOOK_URL"
		export REAL_WEBHOOK_URL
	fi

	export GIT_ROOT
	export SCRIPT
	export CHANNEL
	export REAL_TOKEN
	export REAL_WEBHOOK_URL

	return 0
}

setup() {
	source "$SCRIPT"
	source "$GIT_ROOT/lib/parse-payload.sh"

	_SLACK_WORKSPACE=$(mktemp -d "${BATS_TEST_TMPDIR}/acceptance-tests.workspace.XXXXXX")
	export _SLACK_WORKSPACE

	SLACK_BOT_USER_OAUTH_TOKEN="test-token"
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

	TEST_PAYLOAD_FILE=$(mktemp acceptance-tests.test-payload.XXXXXX)

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
	rm -rf "$_SLACK_WORKSPACE"
	rm -f "$TEST_PAYLOAD_FILE"
	return 0
}

########################################################
# Acceptance Tests
########################################################

@test "acceptance:: comprehensive message with all block types" {
	if [[ -z "$REAL_TOKEN" ]]; then
		skip "REAL_TOKEN is required for acceptance tests"
	fi

	local token="$REAL_TOKEN"
	DRY_RUN="false"

	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "acceptance") | .plan[0].params.blocks' "$GIT_ROOT/examples/acceptance.yaml")

	if ! echo "$blocks_json" | jq . >/dev/null 2>&1; then
		echo "Invalid blocks_json from acceptance.yaml" >&2
		echo "$blocks_json" >&2
		return 1
	fi

	ACCEPTANCE_TEST_FILE=$(mktemp acceptance-tests.test-upload.XXXXXX)
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
	if [[ -z "$REAL_TOKEN" ]]; then
		skip "REAL_TOKEN is required for acceptance tests"
	fi

	local token="$REAL_TOKEN"
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

	run "$SCRIPT" <"$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "version"
	echo "$output" | grep -q "timestamp"
	echo "$output" | grep -q "main:: parsing payload"
	echo "$output" | grep -q "load_input_payload_params:: loading params from params.raw"
	echo "$output" | grep -q "main:: creating Concourse metadata"
	echo "$output" | grep -q "main:: sending notification"
	echo "$output" | grep -q "main:: finished running send-to-slack.sh successfully"
}

@test "acceptance:: params.from_file" {
	if [[ -z "$REAL_TOKEN" ]]; then
		skip "REAL_TOKEN is required for acceptance tests"
	fi

	local token="$REAL_TOKEN"
	DRY_RUN="false"

	ACCEPTANCE_PAYLOAD_FILE=$(mktemp acceptance-tests.acceptance-payload.XXXXXX)
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

	run "$SCRIPT" <"$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "version"
	echo "$output" | grep -q "timestamp"
	echo "$output" | grep -q "main:: parsing payload"
	echo "$output" | grep -q "load_input_payload_params:: loading params from file"
	echo "$output" | grep -q "main:: creating Concourse metadata"
	echo "$output" | grep -q "main:: sending notification"
	echo "$output" | grep -q "main:: finished running send-to-slack.sh successfully"

	[[ -f "$ACCEPTANCE_PAYLOAD_FILE" ]] && rm -f "$ACCEPTANCE_PAYLOAD_FILE"
}

@test "acceptance:: blocks from_file" {
	if [[ -z "$REAL_TOKEN" ]]; then
		skip "REAL_TOKEN is required for acceptance tests"
	fi

	local token="$REAL_TOKEN"
	DRY_RUN="false"

	local block_file_1 block_file_2 block_file_3
	block_file_1="$GIT_ROOT/examples/fixtures/blocks-from-file.json"
	block_file_2="$GIT_ROOT/examples/fixtures/blocks-from-file-2.json"
	block_file_3="$GIT_ROOT/examples/fixtures/blocks-from-file-3.json"

	mkdir -p output
	echo "Example file for blocks-from-file-3" >output/example.txt
	trap 'rm -rf output' EXIT

	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		--arg dry_run "$DRY_RUN" \
		--arg block_file_1 "$block_file_1" \
		--arg block_file_2 "$block_file_2" \
		--arg block_file_3 "$block_file_3" \
		--arg token "$token" \
		'{
			source: {
				slack_bot_user_oauth_token: $token
			},
			params: {
				channel: $channel,
				dry_run: $dry_run,
				blocks: [
					{
						header: {
							text: {
								type: "plain_text",
								text: "Blocks from_file Test"
							}
						}
					},
					{ from_file: $block_file_1 },
					{ from_file: $block_file_2 },
					{ from_file: $block_file_3 }
				]
			}
		}')
	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	if ! jq . "$TEST_PAYLOAD_FILE" >/dev/null 2>&1; then
		echo "Invalid JSON in test payload file" >&2
		cat "$TEST_PAYLOAD_FILE" >&2
		rm -rf output
		return 1
	fi

	run "$SCRIPT" <"$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "version"
	echo "$output" | grep -q "timestamp"
	echo "$output" | grep -q "main:: parsing payload"
	echo "$output" | grep -q "process_blocks:: expanded block from file"
	echo "$output" | grep -q "main:: creating Concourse metadata"
	echo "$output" | grep -q "main:: sending notification"
	echo "$output" | grep -q "main:: finished running send-to-slack.sh successfully"
}

@test "acceptance:: file block from prior job with 644 perms" {
	if [[ -z "$REAL_TOKEN" ]]; then
		skip "REAL_TOKEN is required for acceptance tests"
	fi

	local token="$REAL_TOKEN"
	DRY_RUN="false"

	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "acceptance") | .plan[0].params.blocks' "$GIT_ROOT/examples/acceptance.yaml")

	if ! echo "$blocks_json" | jq . >/dev/null 2>&1; then
		echo "Invalid blocks_json from acceptance.yaml" >&2
		echo "$blocks_json" >&2
		return 1
	fi

	# Simulate artifact created by a prior Concourse job under a different user with 0644 perms
	ACCEPTANCE_TEST_FILE=$(mktemp "${BATS_TEST_TMPDIR}/acceptance-tests.test-upload-644.XXXXXX")
	echo "Artifact created in prior step" >"$ACCEPTANCE_TEST_FILE"
	chmod 644 "$ACCEPTANCE_TEST_FILE"
	local mode
	mode=$(stat -c "%a" "$ACCEPTANCE_TEST_FILE" 2>/dev/null || stat -f "%OLp" "$ACCEPTANCE_TEST_FILE" 2>/dev/null || echo "unknown")

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

	run "$SCRIPT" <"$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "version"
	echo "$output" | grep -q "timestamp"
	echo "$output" | grep -q "main:: parsing payload"
	echo "$output" | grep -q "main:: creating Concourse metadata"
	echo "$output" | grep -q "main:: sending notification"
	echo "$output" | grep -q "main:: finished running send-to-slack.sh successfully"
}

@test "acceptance:: crosspost" {
	if [[ -z "$REAL_TOKEN" ]]; then
		skip "REAL_TOKEN is required for acceptance tests"
	fi

	local token="$REAL_TOKEN"
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
					channels: [$channel],
					text: "See the original message"
				}
			}
		}' >"$TEST_PAYLOAD_FILE"

	if ! jq . "$TEST_PAYLOAD_FILE" >/dev/null 2>&1; then
		echo "Invalid JSON in test payload file" >&2
		cat "$TEST_PAYLOAD_FILE" >&2
		return 1
	fi

	run "$SCRIPT" <"$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "version"
	echo "$output" | grep -q "timestamp"
	echo "$output" | grep -q "main:: parsing payload"
	echo "$output" | grep -q "main:: creating Concourse metadata"
	echo "$output" | grep -q "main:: sending notification"
	echo "$output" | grep -q "main:: finished running send-to-slack.sh successfully"

	local send_count
	send_count=$(echo "$output" | grep -c "send_notification:: message delivered successfully via api")
	[[ "$send_count" -ge 2 ]]
}

@test "acceptance:: thread reply with thread_ts" {
	if [[ -z "$REAL_TOKEN" ]]; then
		skip "REAL_TOKEN is required for acceptance tests"
	fi

	local token="$REAL_TOKEN"
	DRY_RUN="false"

	local parent_response
	parent_response=$(curl -s -X POST \
		-H "Authorization: Bearer $token" \
		-H "Content-Type: application/json" \
		-d "$(jq -n --arg channel "$CHANNEL" '{
			channel: $channel,
			text: "Parent message for thread reply test"
		}')" \
		"https://slack.com/api/chat.postMessage")

	if ! echo "$parent_response" | jq -e '.ok == true' >/dev/null 2>&1; then
		echo "Failed to send parent message: $(echo "$parent_response" | jq -r '.error // "unknown"')" >&2
		skip "Could not send parent message"
	fi

	local thread_ts
	thread_ts=$(echo "$parent_response" | jq -r '.ts')

	if [[ -z "$thread_ts" ]]; then
		echo "No timestamp in parent message response" >&2
		skip "Could not get parent message timestamp"
	fi

	local blocks_json
	blocks_json=$(yq -o json -r '.jobs[] | select(.name == "acceptance") | .plan[0].params.blocks' "$GIT_ROOT/examples/acceptance.yaml")

	if ! echo "$blocks_json" | jq . >/dev/null 2>&1; then
		echo "Invalid blocks_json from acceptance.yaml" >&2
		echo "$blocks_json" >&2
		return 1
	fi

	ACCEPTANCE_TEST_FILE=$(mktemp acceptance-tests.test-upload.XXXXXX)
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

	run "$SCRIPT" <"$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "version"
	echo "$output" | grep -q "timestamp"
	echo "$output" | grep -q "main:: parsing payload"
	echo "$output" | grep -q "main:: creating Concourse metadata"
	echo "$output" | grep -q "main:: sending notification"

	local parsed_payload_file
	parsed_payload_file=$(mktemp acceptance-tests.parsed-payload.XXXXXX)
	trap 'rm -f "$parsed_payload_file" 2>/dev/null || true' EXIT
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

@test "acceptance:: thread.replies without create_thread" {
	if [[ -z "$REAL_TOKEN" ]]; then
		skip "REAL_TOKEN is required for acceptance tests"
	fi

	local token="$REAL_TOKEN"
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
						header: {
							text: {
								type: "plain_text",
								text: "Thread parent"
							}
						}
					}
				],
				thread: {
					replies: [
						{
							blocks: [
								{
									section: {
										type: "text",
										text: {
											type: "mrkdwn",
											text: "Thread reply 1 via thread.replies"
										}
									}
								}
							]
						},
						{
							blocks: [
								{
									section: {
										type: "text",
										text: {
											type: "mrkdwn",
											text: "Thread reply 2 via thread.replies"
										}
									}
								}
							]
						}
					]
				}
			}
		}' >"$TEST_PAYLOAD_FILE"

	if ! jq . "$TEST_PAYLOAD_FILE" >/dev/null 2>&1; then
		echo "Invalid JSON in test payload file" >&2
		cat "$TEST_PAYLOAD_FILE" >&2
		return 1
	fi

	run "$SCRIPT" <"$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "main:: parsing payload"
	echo "$output" | grep -q "main:: sending notification"
	echo "$output" | grep -q "send_thread_replies:: sending 2 thread reply(s)"
	echo "$output" | grep -q "reply 1 of 2 sent"
	echo "$output" | grep -q "reply 2 of 2 sent"
	echo "$output" | grep -q "main:: finished running send-to-slack.sh successfully"

	local send_count
	send_count=$(echo "$output" | grep -c "send_notification:: message delivered successfully via api")
	[[ "$send_count" -ge 3 ]]
}

@test "acceptance:: thread.replies with thread_ts" {
	if [[ -z "$REAL_TOKEN" ]]; then
		skip "REAL_TOKEN is required for acceptance tests"
	fi

	local token="$REAL_TOKEN"
	DRY_RUN="false"

	local parent_response
	parent_response=$(curl -s -X POST \
		-H "Authorization: Bearer ${token}" \
		-H "Content-Type: application/json; charset=utf-8" \
		-d "$(jq -n \
			--arg channel "$CHANNEL" \
			'{
				channel: $channel,
				text: "Parent message for thread.replies test"
			}')" \
		"https://slack.com/api/chat.postMessage")

	if ! echo "$parent_response" | jq -e '.ok == true' >/dev/null 2>&1; then
		echo "Failed to send parent message: $(echo "$parent_response" | jq -r '.error // "unknown"')" >&2
		skip "Could not send parent message"
	fi

	local thread_ts
	thread_ts=$(echo "$parent_response" | jq -r '.ts')

	if [[ -z "$thread_ts" ]]; then
		echo "No timestamp in parent message response" >&2
		skip "Could not get parent message timestamp"
	fi

	jq -n \
		--arg token "$token" \
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
				blocks: [
					{
						section: {
							type: "text",
							text: {
								type: "mrkdwn",
								text: "Message sent into existing thread via thread_ts"
							}
						}
					}
				],
				thread: {
					replies: [
						{
							blocks: [
								{
									section: {
										type: "text",
										text: {
											type: "mrkdwn",
											text: "Thread reply 1 via thread.replies"
										}
									}
								}
							]
						},
						{
							blocks: [
								{
									section: {
										type: "text",
										text: {
											type: "mrkdwn",
											text: "Thread reply 2 via thread.replies"
										}
									}
								}
							]
						}
					]
				}
			}
		}' >"$TEST_PAYLOAD_FILE"

	if ! jq . "$TEST_PAYLOAD_FILE" >/dev/null 2>&1; then
		echo "Invalid JSON in test payload file" >&2
		cat "$TEST_PAYLOAD_FILE" >&2
		return 1
	fi

	run "$SCRIPT" <"$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "main:: parsing payload"
	echo "$output" | grep -q "main:: sending notification"
	echo "$output" | grep -q "send_thread_replies:: sending 2 thread reply(s)"
	echo "$output" | grep -q "reply 1 of 2 sent"
	echo "$output" | grep -q "reply 2 of 2 sent"
	echo "$output" | grep -q "main:: finished running send-to-slack.sh successfully"

	local send_count
	send_count=$(echo "$output" | grep -c "send_notification:: message delivered successfully via api")
	[[ "$send_count" -ge 3 ]]
}

@test "acceptance:: actions block button sends hello world to channel" {
	if [[ -z "$REAL_TOKEN" ]]; then
		skip "REAL_TOKEN is required for acceptance tests"
	fi

	local token="$REAL_TOKEN"
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
	echo "acceptance_test:: Channel Message Button"
	echo "=========================================="
	echo "1. Check Slack channel: ${CHANNEL}"
	echo "2. Click the 'Send to Channel' button"
	echo "3. Verify 'Hello, world!' message appears in the same channel"
	echo "=========================================="
}

@test "acceptance:: actions block button sends hello world to user" {
	if [[ -z "$REAL_TOKEN" ]]; then
		skip "REAL_TOKEN is required for acceptance tests"
	fi

	local token="$REAL_TOKEN"
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
	echo "acceptance_test:: User DM Button"
	echo "=========================================="
	echo "1. Check Slack channel: ${CHANNEL}"
	echo "2. Click the 'Send to Me' button"
	echo "3. Verify 'Hello, world!' message appears in your DMs"
	echo "=========================================="
}

@test "acceptance:: slack-native format with all block types" {
	if [[ -z "$REAL_TOKEN" ]]; then
		skip "REAL_TOKEN is required for acceptance tests"
	fi

	local token="$REAL_TOKEN"
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
	echo "acceptance_test:: Slack Native Format"
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

@test "acceptance:: webhook posts message end to end" {
	if [[ -z "${REAL_WEBHOOK_URL:-}" ]]; then
		skip "SLACK_WEBHOOK_URL is required for webhook acceptance tests"
	fi

	local webhook_url="$REAL_WEBHOOK_URL"
	DRY_RUN="false"

	jq -n \
		--arg url "$webhook_url" \
		--arg dry_run "$DRY_RUN" \
		'{
			source: {
				webhook_url: $url
			},
			params: {
				dry_run: $dry_run,
				blocks: [
					{
						section: {
							type: "text",
							text: {
								type: "mrkdwn",
								text: "acceptance test Incoming Webhook end to end"
							}
						}
					}
				]
			}
		}' >"$TEST_PAYLOAD_FILE"

	if ! jq . "$TEST_PAYLOAD_FILE" >/dev/null 2>&1; then
		echo "Invalid JSON in test payload file" >&2
		cat "$TEST_PAYLOAD_FILE" >&2
		return 1
	fi

	run env -u SLACK_BOT_USER_OAUTH_TOKEN "$SCRIPT" <"$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "version"
	echo "$output" | grep -q "timestamp"
	echo "$output" | grep -q "main:: parsing payload"
	echo "$output" | grep -q "load_configuration:: method=webhook"
	echo "$output" | grep -q "main:: creating Concourse metadata"
	echo "$output" | grep -q "main:: sending notification"
	echo "$output" | grep -q "send_notification:: message delivered successfully via webhook"
	echo "$output" | grep -q "main:: finished running send-to-slack.sh successfully"
}

@test "acceptance:: webhook skips thread replies and crosspost" {
	if [[ -z "${REAL_WEBHOOK_URL:-}" ]]; then
		skip "SLACK_WEBHOOK_URL is required for webhook acceptance tests"
	fi

	local webhook_url="$REAL_WEBHOOK_URL"
	DRY_RUN="false"

	jq -n \
		--arg url "$webhook_url" \
		--arg dry_run "$DRY_RUN" \
		--arg ch "$CHANNEL" \
		'{
			source: {
				webhook_url: $url
			},
			params: {
				dry_run: $dry_run,
				blocks: [
					{
						section: {
							type: "text",
							text: {
								type: "plain_text",
								text: "Webhook parent with skipped thread and crosspost"
							}
						}
					}
				],
				thread: {
					replies: [
						{
							blocks: [
								{
									section: {
										type: "text",
										text: {
											type: "plain_text",
											text: "Thread reply must not send via webhook"
										}
									}
								}
							]
						}
					]
				},
				crosspost: {
					channels: [$ch],
					text: "Crosspost must not run via webhook"
				}
			}
		}' >"$TEST_PAYLOAD_FILE"

	if ! jq . "$TEST_PAYLOAD_FILE" >/dev/null 2>&1; then
		echo "Invalid JSON in test payload file" >&2
		cat "$TEST_PAYLOAD_FILE" >&2
		return 1
	fi

	run env -u SLACK_BOT_USER_OAUTH_TOKEN "$SCRIPT" <"$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "delivery method webhook does not support thread replies, skipping send_thread_replies"
	echo "$output" | grep -q "delivery method webhook does not support crosspost, skipping crosspost_notification"
	echo "$output" | grep -q "main:: finished running send-to-slack.sh successfully"

	local send_count
	send_count=$(echo "$output" | grep -c "send_notification:: message delivered successfully via webhook")
	[[ "$send_count" -eq 1 ]]
}

@test "acceptance:: chat.postEphemeral via params.ephemeral_user" {
	if [[ -z "$REAL_TOKEN" ]]; then
		skip "REAL_TOKEN is required for acceptance tests"
	fi

	if [[ -z "${EPHEMERAL_USER:-}" ]]; then
		skip "EPHEMERAL_USER is required for ephemeral acceptance tests"
	fi

	local token="$REAL_TOKEN"
	local dry_run="false"
	local ephemeral_user="$EPHEMERAL_USER"

	jq -n \
		--arg token "$token" \
		--arg channel "$CHANNEL" \
		--arg dry_run "$dry_run" \
		--arg ephemeral_user "$ephemeral_user" \
		'{
			source: { slack_bot_user_oauth_token: $token },
			params: {
				channel: $channel,
				dry_run: $dry_run,
				ephemeral_user: $ephemeral_user,
				text: "acceptance test chat.postEphemeral",
				blocks: [
					{
						section: {
							type: "text",
							text: {
								type: "mrkdwn",
								text: "acceptance: ephemeral message for one user only"
							}
						}
					}
				]
			}
		}' >"$TEST_PAYLOAD_FILE"

	if ! jq . "$TEST_PAYLOAD_FILE" >/dev/null 2>&1; then
		echo "Invalid JSON in test payload file" >&2
		cat "$TEST_PAYLOAD_FILE" >&2
		return 1
	fi

	run "$SCRIPT" <"$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "version"
	echo "$output" | grep -q "timestamp"
	echo "$output" | grep -q "main:: parsing payload"
	echo "$output" | grep -q "main:: chat.postEphemeral does not support thread replies or crosspost, skipping send_thread_replies and crosspost_notification"
	echo "$output" | grep -q "main:: creating Concourse metadata"
	echo "$output" | grep -q "main:: sending notification"
	echo "$output" | grep -q "send_notification:: message delivered successfully via api"
	echo "$output" | grep -q "main:: finished running send-to-slack.sh successfully"
}

@test "acceptance:: post_message then chat.update" {
	if [[ -z "$REAL_TOKEN" ]]; then
		skip "REAL_TOKEN is required for acceptance tests"
	fi

	local token="$REAL_TOKEN"
	local dry_run="false"
	local post_payload_file
	local version_file
	local update_payload_file

	post_payload_file=$(mktemp "${BATS_TEST_TMPDIR}/acceptance-update-post.XXXXXX")
	version_file=$(mktemp "${BATS_TEST_TMPDIR}/acceptance-update-version.XXXXXX")
	update_payload_file=$(mktemp "${BATS_TEST_TMPDIR}/acceptance-update-put.XXXXXX")
	# EXIT: cleanup when the test subshell exits. RETURN would run when bats `run` returns and delete version_file before jq reads it.
	trap 'rm -f "$post_payload_file" "$version_file" "$update_payload_file" 2>/dev/null || true' EXIT

	jq -n \
		--arg token "$token" \
		--arg channel "$CHANNEL" \
		--arg dry_run "$dry_run" \
		'{
			source: { slack_bot_user_oauth_token: $token },
			params: {
				channel: $channel,
				dry_run: $dry_run,
				text: "acceptance test post for chat.update",
				blocks: [
					{
						section: {
							type: "text",
							text: { type: "mrkdwn", text: "acceptance: before chat.update" }
						}
					}
				]
			}
		}' >"$post_payload_file"

	if ! jq . "$post_payload_file" >/dev/null 2>&1; then
		echo "Invalid JSON in post payload" >&2
		return 1
	fi

	if ! env SEND_TO_SLACK_OUTPUT="$version_file" "$SCRIPT" <"$post_payload_file"; then
		echo "acceptance post_message then chat.update:: first send-to-slack run failed" >&2
		return 1
	fi

	local message_ts
	message_ts=$(jq -r '.version.message_ts // empty' "$version_file")
	if [[ -z "$message_ts" || "$message_ts" == "null" ]]; then
		echo "acceptance post_message then chat.update:: missing version.message_ts" >&2
		cat "$version_file" >&2
		return 1
	fi

	local update_channel
	update_channel=$(jq -r 'first((.metadata // [])[] | select(.name == "channel") | .value) // empty' "$version_file")
	if [[ -z "$update_channel" || "$update_channel" == "null" ]]; then
		update_channel="$CHANNEL"
	fi

	jq -n \
		--arg token "$token" \
		--arg channel "$update_channel" \
		--arg dry_run "$dry_run" \
		--arg message_ts "$message_ts" \
		'{
			source: { slack_bot_user_oauth_token: $token },
			params: {
				channel: $channel,
				dry_run: $dry_run,
				message_ts: $message_ts,
				text: "acceptance test after chat.update",
				blocks: [
					{
						section: {
							type: "text",
							text: { type: "mrkdwn", text: "acceptance: after chat.update" }
						}
					}
				]
			}
		}' >"$update_payload_file"

	if ! jq . "$update_payload_file" >/dev/null 2>&1; then
		echo "Invalid JSON in update payload" >&2
		return 1
	fi

	run env SEND_TO_SLACK_OUTPUT="$version_file" "$SCRIPT" <"$update_payload_file"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "main:: updating existing Slack message via chat.update"
	echo "$output" | grep -q "version"
	echo "$output" | grep -q "main:: creating Concourse metadata"
	echo "$output" | grep -q "main:: finished running send-to-slack.sh successfully"

	local updated_ts
	updated_ts=$(jq -r '.version.message_ts // empty' "$version_file")
	if [[ -z "$updated_ts" || "$updated_ts" == "null" ]]; then
		echo "acceptance post_message then chat.update:: missing version.message_ts after update" >&2
		cat "$version_file" >&2
		return 1
	fi
}

@test "acceptance:: webhook rejects params.ephemeral_user at parse time" {
	if [[ -z "${REAL_WEBHOOK_URL:-}" ]]; then
		skip "SLACK_WEBHOOK_URL is required for webhook acceptance tests"
	fi

	local webhook_url="$REAL_WEBHOOK_URL"
	local dry_run="true"
	local payload_file

	payload_file=$(mktemp "${BATS_TEST_TMPDIR}/acceptance-webhook-ephemeral-reject.XXXXXX")
	trap 'rm -f "$payload_file" 2>/dev/null || true' RETURN

	jq -n \
		--arg url "$webhook_url" \
		--arg dry_run "$dry_run" \
		--arg ephemeral_user "U0123456789" \
		'{
			source: { webhook_url: $url },
			params: {
				dry_run: $dry_run,
				ephemeral_user: $ephemeral_user,
				blocks: [
					{
						section: {
							type: "text",
							text: {
								type: "plain_text",
								text: "acceptance: webhook cannot use ephemeral_user"
							}
						}
					}
				]
			}
		}' >"$payload_file"

	if ! jq . "$payload_file" >/dev/null 2>&1; then
		echo "Invalid JSON in test payload file" >&2
		return 1
	fi

	run env -u SLACK_BOT_USER_OAUTH_TOKEN "$SCRIPT" <"$payload_file"
	[[ "$status" -ne 0 ]]
	echo "$output" | grep -q "load_configuration:: params.ephemeral_user requires API delivery with a bot token, not webhook"
}

@test "acceptance:: webhook rejects params.message_ts" {
	if [[ -z "${REAL_WEBHOOK_URL:-}" ]]; then
		skip "SLACK_WEBHOOK_URL is required for webhook acceptance tests"
	fi

	local webhook_url="$REAL_WEBHOOK_URL"
	local dry_run="true"
	local payload_file

	payload_file=$(mktemp "${BATS_TEST_TMPDIR}/acceptance-webhook-update-reject.XXXXXX")
	trap 'rm -f "$payload_file" 2>/dev/null || true' RETURN

	jq -n \
		--arg url "$webhook_url" \
		--arg dry_run "$dry_run" \
		--arg channel "$CHANNEL" \
		--arg message_ts "1234567890.000001" \
		'{
			source: { webhook_url: $url },
			params: {
				channel: $channel,
				dry_run: $dry_run,
				message_ts: $message_ts,
				blocks: [
					{
						section: {
							type: "text",
							text: {
								type: "plain_text",
								text: "acceptance: webhook cannot use message_ts"
							}
						}
					}
				]
			}
		}' >"$payload_file"

	if ! jq . "$payload_file" >/dev/null 2>&1; then
		echo "Invalid JSON in test payload file" >&2
		return 1
	fi

	run env -u SLACK_BOT_USER_OAUTH_TOKEN "$SCRIPT" <"$payload_file"
	[[ "$status" -ne 0 ]]
	echo "$output" | grep -q "main:: params.message_ts requires API delivery, not webhook"
}
