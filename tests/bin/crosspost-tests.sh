#!/usr/bin/env bats
#
# Test file for crosspost.sh (crosspost_notification)
#

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		fail "Failed to get git root"
	fi

	SCRIPT="$GIT_ROOT/bin/send-to-slack.sh"
	if [[ ! -f "$SCRIPT" ]]; then
		fail "Script not found: $SCRIPT"
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
	cd "$GIT_ROOT" || return 1
	source "$SCRIPT"
	source "$GIT_ROOT/lib/parse-payload.sh"
	source "$GIT_ROOT/bin/crosspost.sh"

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

	TEST_PAYLOAD_FILE=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.test-payload.XXXXXX")
	_SLACK_WORKSPACE=$(mktemp -d "${BATS_TEST_TMPDIR}/send-to-slack-tests.workspace.XXXXXX")

	export SLACK_BOT_USER_OAUTH_TOKEN
	export CHANNEL
	export MESSAGE
	export DRY_RUN
	export SHOW_METADATA
	export SHOW_PAYLOAD
	export TEST_PAYLOAD_FILE
	export _SLACK_WORKSPACE

	return 0
}

teardown() {
	rm -f "${TEST_PAYLOAD_FILE}"
	[[ -n "$input_payload" ]] && rm -f "$input_payload"
	return 0
}

########################################################
# crosspost_notification
########################################################

@test "crosspost_notification:: skips when crosspost is empty" {
	local input_payload
	input_payload=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.test-crosspost.XXXXXX")
	jq -n '{
		source: { slack_bot_user_oauth_token: "test-token" },
		params: { channel: "#test", blocks: [] }
	}' >"$input_payload"

	run crosspost_notification "$input_payload"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "crosspost is empty, skipping"

	rm -f "$input_payload"
}

@test "crosspost_notification:: skips when channel not set" {
	local input_payload
	input_payload=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.test-crosspost.XXXXXX")
	jq -n '{
		source: { slack_bot_user_oauth_token: "test-token" },
		params: {
			channel: "#test",
			blocks: [],
			crosspost: {
				blocks: []
			}
		}
	}' >"$input_payload"

	run crosspost_notification "$input_payload"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "channel not set, skipping"

	rm -f "$input_payload"
}

@test "crosspost_notification:: accepts blocks like regular message" {
	DRY_RUN="true"
	NOTIFICATION_PERMALINK="https://workspace.slack.com/archives/C123/p123"
	local input_payload
	input_payload=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.test-crosspost.XXXXXX")
	jq -n '{
		source: { slack_bot_user_oauth_token: "test-token" },
		params: {
			channel: "#test",
			blocks: [{
				section: {
					type: "text",
					text: { type: "plain_text", text: "Primary message" }
				}
			}],
			crosspost: {
				channel: ["#channel1"],
				blocks: [{
					section: {
						type: "text",
						text: { type: "mrkdwn", text: "Crosspost with full blocks support" }
					}
				}]
			}
		}
	}' >"$input_payload"

	run crosspost_notification "$input_payload"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "parsing crosspost payload for channel"
	echo "$output" | grep -q "sending notification to channel"

	rm -f "$input_payload"
}

@test "crosspost_notification:: processes multiple channels" {
	DRY_RUN="true"
	NOTIFICATION_PERMALINK="https://workspace.slack.com/archives/C123/p123"
	local input_payload
	input_payload=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.test-crosspost.XXXXXX")
	jq -n '{
		source: { slack_bot_user_oauth_token: "test-token" },
		params: {
			channel: "#test",
			blocks: [{
				section: {
					type: "text",
					text: { type: "plain_text", text: "Primary" }
				}
			}],
			crosspost: {
				channel: ["#channel1", "#channel2", "#channel3"],
				blocks: [{
					section: {
						type: "text",
						text: { type: "plain_text", text: "Crosspost" }
					}
				}]
			}
		}
	}' >"$input_payload"

	run crosspost_notification "$input_payload"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "parsing crosspost payload for channel"
	echo "$output" | grep -q "sending notification to channel"

	rm -f "$input_payload"
}

@test "crosspost_notification:: accepts single channel string" {
	DRY_RUN="true"
	NOTIFICATION_PERMALINK="https://workspace.slack.com/archives/C123/p123"
	local input_payload
	input_payload=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.test-crosspost.XXXXXX")
	jq -n '{
		source: { slack_bot_user_oauth_token: "test-token" },
		params: {
			channel: "#primary",
			blocks: [{
				section: {
					type: "text",
					text: { type: "plain_text", text: "Primary" }
				}
			}],
			crosspost: {
				channel: "#channel1",
				blocks: [{
					section: {
						type: "text",
						text: { type: "plain_text", text: "Crosspost" }
					}
				}]
			}
		}
	}' >"$input_payload"

	run crosspost_notification "$input_payload"
	[[ "$status" -eq 0 ]]

	rm -f "$input_payload"
}

@test "crosspost_notification:: supports channels alias" {
	DRY_RUN="true"
	NOTIFICATION_PERMALINK="https://workspace.slack.com/archives/C123/p123"
	local input_payload
	input_payload=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.test-crosspost.XXXXXX")
	jq -n '{
		source: { slack_bot_user_oauth_token: "test-token" },
		params: {
			channel: "#primary",
			blocks: [{
				section: {
					type: "text",
					text: { type: "plain_text", text: "Primary" }
				}
			}],
			crosspost: {
				channels: ["#channel1", "#channel2"],
				blocks: [{
					section: {
						type: "text",
						text: { type: "plain_text", text: "Crosspost using channels alias" }
					}
				}]
			}
		}
	}' >"$input_payload"

	run crosspost_notification "$input_payload"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "sending to 2 channel(s)"

	rm -f "$input_payload"
}

@test "crosspost_notification:: supports header and context blocks" {
	DRY_RUN="true"
	NOTIFICATION_PERMALINK="https://workspace.slack.com/archives/C123/p123"
	local input_payload
	input_payload=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.test-crosspost.XXXXXX")
	jq -n '{
		source: { slack_bot_user_oauth_token: "test-token" },
		params: {
			channel: "#test",
			blocks: [{
				section: {
					type: "text",
					text: { type: "plain_text", text: "Primary" }
				}
			}],
			crosspost: {
				channel: ["#channel1"],
				blocks: [
					{
						header: {
							text: { type: "plain_text", text: "Crosspost Header" }
						}
					},
					{
						section: {
							type: "text",
							text: { type: "mrkdwn", text: "Message body" }
						}
					},
					{
						context: {
							elements: [
								{ type: "mrkdwn", text: "Footer info" }
							]
						}
					}
				]
			}
		}
	}' >"$input_payload"

	run crosspost_notification "$input_payload"
	[[ "$status" -eq 0 ]]

	rm -f "$input_payload"
}

@test "crosspost_notification:: auto-appends permalink by default" {
	DRY_RUN="true"
	NOTIFICATION_PERMALINK="https://workspace.slack.com/archives/C123/p123"
	local input_payload
	input_payload=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.test-crosspost.XXXXXX")
	jq -n '{
		source: { slack_bot_user_oauth_token: "test-token" },
		params: {
			channel: "#test",
			blocks: [{
				section: {
					type: "text",
					text: { type: "plain_text", text: "Primary" }
				}
			}],
			crosspost: {
				channel: "#channel1",
				blocks: [{
					section: {
						type: "text",
						text: { type: "plain_text", text: "Crosspost message" }
					}
				}]
			}
		}
	}' >"$input_payload"

	local crosspost_params
	crosspost_params=$(jq '.params.crosspost | del(.channel, .no_link)' "$input_payload")
	# shellcheck disable=SC2016
	local permalink_block='{"context": {"elements": [{"type": "mrkdwn", "text": "<$NOTIFICATION_PERMALINK|View original message>"}]}}'
	crosspost_params=$(echo "$crosspost_params" | jq --argjson link "$permalink_block" '.blocks = (.blocks // []) + [$link]')

	local block_count
	block_count=$(echo "$crosspost_params" | jq '.blocks | length')
	[[ "$block_count" -eq 2 ]]

	echo "$crosspost_params" | jq -e '.blocks[-1].context.elements[0].text | contains("NOTIFICATION_PERMALINK")' >/dev/null

	rm -f "$input_payload"
}

@test "crosspost_notification:: no_link true skips permalink" {
	DRY_RUN="true"
	NOTIFICATION_PERMALINK="https://workspace.slack.com/archives/C123/p123"
	local input_payload
	input_payload=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.test-crosspost.XXXXXX")
	jq -n '{
		source: { slack_bot_user_oauth_token: "test-token" },
		params: {
			channel: "#test",
			blocks: [{
				section: {
					type: "text",
					text: { type: "plain_text", text: "Primary" }
				}
			}],
			crosspost: {
				channel: "#channel1",
				no_link: true,
				blocks: [{
					section: {
						type: "text",
						text: { type: "plain_text", text: "Crosspost without link" }
					}
				}]
			}
		}
	}' >"$input_payload"

	run crosspost_notification "$input_payload"
	[[ "$status" -eq 0 ]]

	rm -f "$input_payload"
}

@test "crosspost_notification:: webhook delivery skips permalink append with warning" {
	DRY_RUN="true"
	DELIVERY_METHOD="webhook"
	NOTIFICATION_PERMALINK="https://workspace.slack.com/archives/C123/p123"

	local input_payload
	input_payload=$(mktemp "${BATS_TEST_TMPDIR}/send-to-slack-tests.test-crosspost.XXXXXX")
	jq -n '{
		source: { webhook_url: "https://hooks.slack.com/services/test" },
		params: {
			blocks: [{
				section: {
					type: "text",
					text: { type: "plain_text", text: "Primary" }
				}
			}],
			crosspost: {
				channel: "#channel1",
				blocks: [{
					section: {
						type: "text",
						text: { type: "plain_text", text: "Crosspost message" }
					}
				}]
			}
		}
	}' >"$input_payload"

	run crosspost_notification "$input_payload"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "webhook delivery does not support permalink, skipping automatic link block"

	rm -f "$input_payload"
}
