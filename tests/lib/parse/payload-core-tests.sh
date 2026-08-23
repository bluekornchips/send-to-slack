#!/usr/bin/env bats
#
# Core parse_payload, load_configuration, process_blocks, sanitize/debug, and unit helpers.
#

load "payload-test-helper.sh"

setup_file() {
	payload_tests_setup_file
}

setup() {
	payload_tests_setup
}

teardown() {
	payload_tests_teardown
}

########################################################
# _validate_block_input_size
########################################################
@test "_validate_block_input_size:: no block_value" {
	run _validate_block_input_size "" "section" 1024
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "block_value is required"
}

@test "_validate_block_input_size:: no block_type" {
	run _validate_block_input_size '{"text":"hello"}' "" 1024
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "block_type is required"
}

@test "_validate_block_input_size:: no max_bytes falls back to MAX_BLOCK_INPUT_BYTES" {
	local block_value
	block_value=$(jq -n '{"text":"hello"}')

	run _validate_block_input_size "$block_value" "section"
	[[ "$status" -eq 0 ]]
}

@test "_validate_block_input_size:: within limit" {
	local block_value
	block_value=$(jq -n '{"text":"hello"}')

	run _validate_block_input_size "$block_value" "section" 1024
	[[ "$status" -eq 0 ]]
}

@test "_validate_block_input_size:: at exact limit" {
	local block_value
	block_value=$(printf '%*s' 10 '' | tr ' ' 'x')

	run _validate_block_input_size "$block_value" "section" 10
	[[ "$status" -eq 0 ]]
}

@test "_validate_block_input_size:: exceeds limit" {
	local block_value
	block_value=$(printf '%*s' 100 '' | tr ' ' 'x')

	run _validate_block_input_size "$block_value" "table" 10
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "exceeds limit"
	echo "$output" | grep -q "table"
}

########################################################
# parse_payload
########################################################

@test "parse_payload:: invalid json input" {
	local invalid_file
	invalid_file=$(mktemp "${BATS_TEST_TMPDIR}/payload-tests.invalid-json.XXXXXX")
	trap 'rm -f "$invalid_file" 2>/dev/null || true' EXIT
	echo "invalid json" >"$invalid_file"

	run parse_payload "$invalid_file"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "invalid JSON"
	rm -f "$invalid_file"
	trap - EXIT

	rm -f "$invalid_file"
}

@test "parse_payload:: webhook_url mode succeeds without token and channel" {
	unset SLACK_BOT_USER_OAUTH_TOKEN
	unset CHANNEL

	local test_payload
	test_payload=$(jq -n '{
		source: {
			webhook_url: "https://hooks.slack.com/services/test"
		},
		params: {
			blocks: [{
				section: {
					type: "text",
					text: { type: "plain_text", text: "Webhook only" }
				}
			}]
		}
	}')
	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "method=webhook"
}

@test "parse_payload:: fails when neither token nor webhook_url is provided" {
	unset SLACK_BOT_USER_OAUTH_TOKEN
	unset WEBHOOK_URL

	local test_payload
	test_payload=$(jq -n '{
		source: {},
		params: {
			blocks: [{
				section: {
					type: "text",
					text: { type: "plain_text", text: "No delivery source" }
				}
			}]
		}
	}')
	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "either source.slack_bot_user_oauth_token or source.webhook_url is required"
}

########################################################
# load_configuration
########################################################

@test "load_configuration:: exports EPHEMERAL_USER when params.ephemeral_user is set" {
	unset EPHEMERAL_USER

	jq -n '{
		source: {
			slack_bot_user_oauth_token: "xoxb-test"
		},
		params: {
			channel: "C123",
			dry_run: true,
			ephemeral_user: "U012AB3CD"
		}
	}' >"$TEST_PAYLOAD_FILE"

	INPUT_PAYLOAD="$TEST_PAYLOAD_FILE"
	export INPUT_PAYLOAD

	if ! load_configuration; then
		fail "load_configuration failed"
	fi
	[[ "${EPHEMERAL_USER:-}" == "U012AB3CD" ]]
}

@test "load_configuration:: fails when ephemeral_user is set with webhook delivery" {
	unset SLACK_BOT_USER_OAUTH_TOKEN
	unset CHANNEL
	unset EPHEMERAL_USER

	jq -n '{
		source: {
			webhook_url: "https://hooks.slack.com/services/test"
		},
		params: {
			ephemeral_user: "U1",
			blocks: [{
				section: {
					type: "text",
					text: { type: "plain_text", text: "x" }
				}
			}]
		}
	}' >"$TEST_PAYLOAD_FILE"

	INPUT_PAYLOAD="$TEST_PAYLOAD_FILE"
	export INPUT_PAYLOAD

	run load_configuration
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "params.ephemeral_user requires API delivery"
}

@test "load_configuration:: fails when params.username is set with webhook delivery" {
	unset SLACK_BOT_USER_OAUTH_TOKEN
	unset CHANNEL

	jq -n '{
		source: {
			webhook_url: "https://hooks.slack.com/services/test"
		},
		params: {
			username: "Deploy Bot",
			blocks: [{
				section: {
					type: "text",
					text: { type: "plain_text", text: "x" }
				}
			}]
		}
	}' >"$TEST_PAYLOAD_FILE"

	INPUT_PAYLOAD="$TEST_PAYLOAD_FILE"
	export INPUT_PAYLOAD

	run load_configuration
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "params.username, params.icon_emoji, and params.icon_url require API delivery"
}

@test "load_configuration:: fails when params.icon_emoji is set with webhook delivery" {
	unset SLACK_BOT_USER_OAUTH_TOKEN
	unset CHANNEL

	jq -n '{
		source: {
			webhook_url: "https://hooks.slack.com/services/test"
		},
		params: {
			icon_emoji: ":robot_face:",
			blocks: [{
				section: {
					type: "text",
					text: { type: "plain_text", text: "x" }
				}
			}]
		}
	}' >"$TEST_PAYLOAD_FILE"

	INPUT_PAYLOAD="$TEST_PAYLOAD_FILE"
	export INPUT_PAYLOAD

	run load_configuration
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "params.username, params.icon_emoji, and params.icon_url require API delivery"
}

@test "load_configuration:: does not set EPHEMERAL_USER when params.ephemeral_user is absent" {
	export EPHEMERAL_USER="stale-from-environment"

	jq -n '{
		source: {
			slack_bot_user_oauth_token: "xoxb-test"
		},
		params: {
			channel: "C123",
			dry_run: true
		}
	}' >"$TEST_PAYLOAD_FILE"

	INPUT_PAYLOAD="$TEST_PAYLOAD_FILE"
	export INPUT_PAYLOAD

	if ! load_configuration; then
		fail "load_configuration failed"
	fi
	[[ -z "${EPHEMERAL_USER:-}" ]]
}

########################################################
# process_blocks, ephemeral user in API payload
########################################################

@test "process_blocks:: includes user field in payload when EPHEMERAL_USER is set" {
	jq -n '{
		source: {
			slack_bot_user_oauth_token: "xoxb-test"
		},
		params: {
			channel: "C123",
			dry_run: true,
			ephemeral_user: "U99",
			blocks: [{
				section: {
					type: "text",
					text: { type: "plain_text", text: "Hello" }
				}
			}]
		}
	}' >"$TEST_PAYLOAD_FILE"

	local payload_output
	payload_output=$(parse_payload "$TEST_PAYLOAD_FILE")

	echo "$payload_output" | jq -e '.user == "U99"' >/dev/null
}

@test "process_blocks:: merges username icon_emoji icon_url from params" {
	jq -n '{
		source: {
			slack_bot_user_oauth_token: "xoxb-test"
		},
		params: {
			channel: "C123",
			dry_run: true,
			username: "Deploy Bot",
			icon_emoji: ":ship:",
			icon_url: "https://example.com/icon.png",
			blocks: [{
				section: {
					type: "text",
					text: { type: "plain_text", text: "Hello" }
				}
			}]
		}
	}' >"$TEST_PAYLOAD_FILE"

	local payload_output
	payload_output=$(parse_payload "$TEST_PAYLOAD_FILE")

	echo "$payload_output" | jq -e '.username == "Deploy Bot"' >/dev/null
	echo "$payload_output" | jq -e '.icon_emoji == ":ship:"' >/dev/null
	echo "$payload_output" | jq -e '.icon_url == "https://example.com/icon.png"' >/dev/null
}

@test "process_blocks:: omits identity keys when params omit or use empty strings" {
	jq -n '{
		source: {
			slack_bot_user_oauth_token: "xoxb-test"
		},
		params: {
			channel: "C123",
			dry_run: true,
			username: "",
			blocks: [{
				section: {
					type: "text",
					text: { type: "plain_text", text: "Hello" }
				}
			}]
		}
	}' >"$TEST_PAYLOAD_FILE"

	local payload_output
	payload_output=$(parse_payload "$TEST_PAYLOAD_FILE")

	echo "$payload_output" | jq -e 'has("username") | not' >/dev/null
}

@test "process_blocks:: does not include user field when EPHEMERAL_USER is unset" {
	jq -n '{
		source: {
			slack_bot_user_oauth_token: "xoxb-test"
		},
		params: {
			channel: "C123",
			dry_run: true,
			blocks: [{
				section: {
					type: "text",
					text: { type: "plain_text", text: "Hello" }
				}
			}]
		}
	}' >"$TEST_PAYLOAD_FILE"

	local payload_output
	payload_output=$(parse_payload "$TEST_PAYLOAD_FILE")

	echo "$payload_output" | jq -e 'has("user") | not' >/dev/null
}

@test "parse_payload:: file blocks fail in webhook mode" {
	unset SLACK_BOT_USER_OAUTH_TOKEN
	unset CHANNEL

	local tmp_file
	tmp_file=$(mktemp "${BATS_TEST_TMPDIR}/payload-tests.file-upload.XXXXXX")
	echo "hello" >"$tmp_file"

	local test_payload
	test_payload=$(jq -n \
		--arg file "$tmp_file" \
		'{
			source: {
				webhook_url: "https://hooks.slack.com/services/test"
			},
			params: {
				blocks: [{
					file: {
						path: $file
					}
				}]
			}
		}')
	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "file uploads are not supported for webhook delivery"

	rm -f "$tmp_file"
}

@test "parse_payload:: missing slack_bot_user_oauth_token" {
	unset SLACK_BOT_USER_OAUTH_TOKEN
	unset WEBHOOK_URL

	local test_payload
	test_payload=$(jq 'del(.source.slack_bot_user_oauth_token)' "$TEST_PAYLOAD_FILE")
	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "either source.slack_bot_user_oauth_token or source.webhook_url is required"
}

@test "parse_payload:: missing channel" {
	unset CHANNEL

	local test_payload
	test_payload=$(jq 'del(.params.channel)' "$TEST_PAYLOAD_FILE")
	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "params.channel is required"
}

@test "parse_payload:: fallback to SLACK_BOT_USER_OAUTH_TOKEN env var when source missing" {
	local test_payload
	test_payload=$(jq '.params.blocks = [{"section": {"type": "text", "text": {"type": "plain_text", "text": "Test"}}}] | .params.channel = "test-channel" | del(.source)' "$TEST_PAYLOAD_FILE")
	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	SLACK_BOT_USER_OAUTH_TOKEN="env-token-value"
	CHANNEL="env-channel-value"
	DRY_RUN="false"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	[[ "$SLACK_BOT_USER_OAUTH_TOKEN" == "env-token-value" ]]

	unset SLACK_BOT_USER_OAUTH_TOKEN
	unset CHANNEL
	unset DRY_RUN
}

@test "parse_payload:: fallback to CHANNEL env var when source missing" {
	local test_payload
	test_payload=$(jq '.params.blocks = [{"section": {"type": "text", "text": {"type": "plain_text", "text": "Test"}}}] | del(.source) | del(.params.channel)' "$TEST_PAYLOAD_FILE")
	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	SLACK_BOT_USER_OAUTH_TOKEN="env-token-value"
	CHANNEL="env-channel-value"
	DRY_RUN="false"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	[[ "$CHANNEL" == "env-channel-value" ]]

	unset SLACK_BOT_USER_OAUTH_TOKEN
	unset CHANNEL
	unset DRY_RUN
}

@test "parse_payload:: fallback to DRY_RUN env var when source missing" {
	local test_payload
	test_payload=$(jq '.params.blocks = [{"section": {"type": "text", "text": {"type": "plain_text", "text": "Test"}}}] | .params.channel = "test-channel" | del(.source) | del(.params.dry_run)' "$TEST_PAYLOAD_FILE")
	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	SLACK_BOT_USER_OAUTH_TOKEN="env-token-value"
	CHANNEL="test-channel"
	DRY_RUN="true"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	[[ "$DRY_RUN" == "true" ]]

	unset SLACK_BOT_USER_OAUTH_TOKEN
	unset CHANNEL
	unset DRY_RUN
}

@test "parse_payload:: fallback to all env vars when source missing" {
	local test_payload
	test_payload=$(jq '.params.blocks = [{"section": {"type": "text", "text": {"type": "plain_text", "text": "Test"}}}] | del(.source) | del(.params.channel) | del(.params.dry_run)' "$TEST_PAYLOAD_FILE")
	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	SLACK_BOT_USER_OAUTH_TOKEN="env-token-value"
	CHANNEL="env-channel-value"
	DRY_RUN="true"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	[[ "$SLACK_BOT_USER_OAUTH_TOKEN" == "env-token-value" ]]
	[[ "$CHANNEL" == "env-channel-value" ]]
	[[ "$DRY_RUN" == "true" ]]

	unset SLACK_BOT_USER_OAUTH_TOKEN
	unset CHANNEL
	unset DRY_RUN
}

@test "parse_payload:: fails when source missing and SLACK_BOT_USER_OAUTH_TOKEN env var not set" {
	local test_payload
	test_payload=$(jq '.params.blocks = [{"section": {"type": "text", "text": {"type": "plain_text", "text": "Test"}}}] | .params.channel = "test-channel" | del(.source)' "$TEST_PAYLOAD_FILE")
	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	unset SLACK_BOT_USER_OAUTH_TOKEN
	CHANNEL="test-channel"
	DRY_RUN="false"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "either source.slack_bot_user_oauth_token or source.webhook_url is required"

	unset CHANNEL
	unset DRY_RUN
}

@test "parse_payload:: fails when source missing and CHANNEL env var not set" {
	local test_payload
	test_payload=$(jq '.params.blocks = [{"section": {"type": "text", "text": {"type": "plain_text", "text": "Test"}}}] | del(.source) | del(.params.channel)' "$TEST_PAYLOAD_FILE")
	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	SLACK_BOT_USER_OAUTH_TOKEN="env-token-value"
	unset CHANNEL
	DRY_RUN="false"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "params.channel is required and missing from payload and environment"

	unset SLACK_BOT_USER_OAUTH_TOKEN
	unset DRY_RUN
}

@test "parse_payload:: source takes precedence over env vars" {
	local test_payload
	test_payload=$(jq '.params.blocks = [{"section": {"type": "text", "text": {"type": "plain_text", "text": "Test"}}}] | .params.channel = "test-channel" | .source.slack_bot_user_oauth_token = "payload-token-value"' "$TEST_PAYLOAD_FILE")
	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	# Call parse_payload directly to check exported variables
	# Capture output to temp file to avoid subshell issues
	local output_file
	output_file=$(mktemp "${BATS_TEST_TMPDIR}/payload-tests.output.XXXXXX")

	if ! parse_payload "$TEST_PAYLOAD_FILE" >"$output_file" 2>&1; then
		cat "$output_file"
		rm -f "$output_file"
		return 1
	fi

	local output
	output=$(cat "$output_file")
	rm -f "$output_file"
	# Should NOT use env vars when source exists
	echo "$output" | grep -vq "Source key not found in payload. Using SLACK_BOT_USER_OAUTH_TOKEN from environment variable"
	echo "$output" | grep -vq "Source key not found in payload. Using CHANNEL from environment variable"
	echo "$output" | grep -vq "Source key not found in payload. Using DRY_RUN from environment variable"
	# Should use payload values
	[[ "$SLACK_BOT_USER_OAUTH_TOKEN" == "payload-token-value" ]]

	unset SLACK_BOT_USER_OAUTH_TOKEN
	unset CHANNEL
	unset DRY_RUN
}

@test "parse_payload:: params.raw" {
	local raw_params
	raw_params=$(
		cat <<-'EOF'
			{
			  "channel": "raw-channel",
			  "blocks": [
			    {
			      "section": {
			        "type": "text",
			        "text": {
			          "type": "plain_text",
			          "text": "Raw message"
			        }
			      }
			    }
			  ]
			}
		EOF
	)

	local test_payload
	test_payload=$(jq -n \
		--arg raw "$raw_params" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				raw: $raw
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "load_input_payload_params:: loading params from params.raw"
}

@test "parse_payload:: params.raw invalid json" {
	local test_payload
	test_payload=$(jq -n '{ params: { raw: "invalid json" } }')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "raw payload is not valid JSON"
}

@test "parse_payload:: params.from_file" {
	local payload_file
	payload_file=$(mktemp "${BATS_TEST_TMPDIR}/payload-tests.params-file.XXXXXX")
	trap 'rm -f "$payload_file" 2>/dev/null || true' EXIT

	# File contains only params (source is preserved from test payload)
	jq -n \
		'{
			channel: "file-channel",
			blocks: [{
				section: {
					type: "text",
					text: { type: "plain_text", text: "File message" }
				}
			}]
		}' >"$payload_file"

	# Test payload must include source section
	local test_payload
	test_payload=$(jq -n \
		--arg file "$payload_file" \
		'{
			source: {
				slack_bot_user_oauth_token: "test-token"
			},
			params: {
				from_file: $file
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "load_input_payload_params:: loading params from file"

	rm -f "$payload_file"
	trap - EXIT
}

@test "parse_payload:: params.from_file not found" {
	local test_payload
	test_payload=$(jq -n '{ params: { from_file: "/nonexistent/file.json" } }')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "not found"
}

@test "parse_payload:: params.from_file invalid json" {
	local payload_file
	payload_file=$(mktemp "${BATS_TEST_TMPDIR}/payload-tests.invalid-params-file.XXXXXX")
	echo "invalid json" >"$payload_file"

	local test_payload
	test_payload=$(jq -n --arg file "$payload_file" '{ params: { from_file: $file } }')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "load_input_payload_params:: loading params from file"

	rm -f "$payload_file"
}

@test "parse_payload:: params.from_file empty path fails" {
	local test_payload
	test_payload=$(jq -n '{ params: { from_file: "" } }')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "params.from_file is empty"
}

@test "parse_payload:: params.from_file path is directory fails" {
	local dir_path
	dir_path=$(mktemp -d "${BATS_TEST_TMPDIR}/payload-tests.dir.XXXXXX")
	trap 'rm -rf "$dir_path" 2>/dev/null || true' EXIT

	local test_payload
	test_payload=$(jq -n --arg dir "$dir_path" '{ params: { from_file: $dir } }')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "path is a directory"

	rm -rf "$dir_path"
	trap - EXIT
}

@test "parse_payload:: params.from_file resolves with SEND_TO_SLACK_PAYLOAD_BASE_DIR" {
	local base_dir
	local params_file
	base_dir=$(mktemp -d "${BATS_TEST_TMPDIR}/payload-tests.base.XXXXXX")

	params_file="${base_dir}/nested/slack-params.json"
	mkdir -p "$(dirname "$params_file")"
	jq -n --arg msg "From base dir" \
		'{"channel": "base-dir-channel", "blocks": [{"section": {"type": "text", "text": {"type": "plain_text", "text": $msg}}}]}' \
		>"$params_file"

	local test_payload
	test_payload=$(jq -n --arg file "nested/slack-params.json" '{
		source: { slack_bot_user_oauth_token: "test-token" },
		params: { from_file: $file }
	}')
	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	SEND_TO_SLACK_PAYLOAD_BASE_DIR="$base_dir"
	export SEND_TO_SLACK_PAYLOAD_BASE_DIR
	run parse_payload "$TEST_PAYLOAD_FILE"
	unset SEND_TO_SLACK_PAYLOAD_BASE_DIR

	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "load_input_payload_params:: loading params from file"

	rm -rf "$base_dir"
}

########################################################
# _sanitize_payload
########################################################

@test "_sanitize_payload:: redacts slack_bot_user_oauth_token to [REDACTED]" {
	local test_payload
	test_payload=$(jq -n '{
		source: {
			slack_bot_user_oauth_token: "xoxb-secret-token-12345"
		},
		params: {
			channel: "test-channel",
			blocks: []
		}
	}')

	local sanitized
	sanitized=$(_sanitize_payload "$test_payload")

	# Token should be redacted
	echo "$sanitized" | jq -e '.source.slack_bot_user_oauth_token == "[REDACTED]"' >/dev/null
	# Other fields should remain
	echo "$sanitized" | jq -e '.params.channel == "test-channel"' >/dev/null
}

@test "_sanitize_payload:: handles payload without source" {
	local test_payload
	test_payload=$(jq -n '{
		params: {
			channel: "test-channel",
			blocks: []
		}
	}')

	local sanitized
	sanitized=$(_sanitize_payload "$test_payload")

	# Should not error and preserve structure
	echo "$sanitized" | jq -e '.params.channel == "test-channel"' >/dev/null
}

@test "_sanitize_payload:: handles payload with source but no token" {
	local test_payload
	test_payload=$(jq -n '{
		source: {
			some_other_field: "value"
		},
		params: {
			channel: "test-channel",
			blocks: []
		}
	}')

	local sanitized
	sanitized=$(_sanitize_payload "$test_payload")

	# Should preserve source structure and add token as [REDACTED]
	echo "$sanitized" | jq -e '.source.some_other_field == "value"' >/dev/null
	echo "$sanitized" | jq -e '.source.slack_bot_user_oauth_token == "[REDACTED]"' >/dev/null
	echo "$sanitized" | jq -e '.params.channel == "test-channel"' >/dev/null
}

@test "_sanitize_payload:: handles invalid JSON" {
	local invalid_json="not valid json {"

	run _sanitize_payload "$invalid_json"
	# Should return the input unchanged (but function returns error code)
	[[ "$status" -eq 1 ]]
	[[ "$output" == "$invalid_json" ]]
}

########################################################
# _log_sanitized_payload
########################################################

@test "_log_sanitized_payload:: logs sanitized payload to stderr" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		'{
			source: {
				slack_bot_user_oauth_token: "xoxb-secret-token-12345"
			},
			params: {
				channel: $channel,
				blocks: [{
					section: {
						type: "text",
						text: { type: "plain_text", text: "Test" }
					}
				}]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	INPUT_PAYLOAD="$TEST_PAYLOAD_FILE"
	export INPUT_PAYLOAD

	run _log_sanitized_payload
	[[ "$status" -eq 0 ]]

	# Should log to stderr (captured in output)
	echo "$output" | grep -q "parse_payload:: input payload (sanitized):"
	# Token should be redacted, not present in original form
	echo "$output" | grep -qv "xoxb-secret-token-12345"
	echo "$output" | grep -q "[REDACTED]"
	# Other fields should be present
	echo "$output" | grep -q "$CHANNEL"
}

@test "_log_sanitized_payload:: handles missing payload file" {
	INPUT_PAYLOAD="/nonexistent/file.json"
	export INPUT_PAYLOAD

	run _log_sanitized_payload
	[[ "$status" -eq 1 ]]
}

########################################################
# parse_payload sanitization logging
########################################################

@test "parse_payload:: logs sanitized payload when params.debug is true" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		'{
			source: {
				slack_bot_user_oauth_token: "xoxb-secret-token-12345"
			},
			params: {
				channel: $channel,
				debug: true,
				blocks: [{
					section: {
						type: "text",
						text: { type: "plain_text", text: "Test message" }
					}
				}]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]

	# Should log sanitized payload when debug is enabled
	echo "$output" | grep -q "parse_payload:: input payload (sanitized):"
	# Token should be redacted, not present in original form
	echo "$output" | grep -qv "xoxb-secret-token-12345"
	echo "$output" | grep -q "[REDACTED]"
	# Channel and other non-sensitive fields should be present
	echo "$output" | grep -q "$CHANNEL"
	echo "$output" | grep -q "Test message"
}

@test "parse_payload:: does not log sanitized payload when params.debug is false" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		'{
			source: {
				slack_bot_user_oauth_token: "xoxb-secret-token-12345"
			},
			params: {
				channel: $channel,
				debug: false,
				blocks: [{
					section: {
						type: "text",
						text: { type: "plain_text", text: "Test message" }
					}
				}]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]

	# Should NOT log sanitized payload when debug is disabled
	echo "$output" | grep -qv "parse_payload:: input payload (sanitized):"
}

@test "parse_payload:: does not log sanitized payload when params.debug is not set" {
	local test_payload
	test_payload=$(jq -n \
		--arg channel "$CHANNEL" \
		'{
			source: {
				slack_bot_user_oauth_token: "xoxb-secret-token-12345"
			},
			params: {
				channel: $channel,
				blocks: [{
					section: {
						type: "text",
						text: { type: "plain_text", text: "Test message" }
					}
				}]
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]

	# Should NOT log sanitized payload when debug is not set (defaults to false)
	echo "$output" | grep -qv "parse_payload:: input payload (sanitized):"
}

@test "parse_payload:: sanitized payload logging works with params.raw when debug enabled" {
	local raw_params
	raw_params=$(jq -n '{
		channel: "raw-channel",
		blocks: [{
			section: {
				type: "text",
				text: { type: "plain_text", text: "Raw params test" }
			}
		}]
	}')

	local test_payload
	test_payload=$(jq -n \
		--arg raw_params "$(echo "$raw_params" | jq -c .)" \
		'{
			source: {
				slack_bot_user_oauth_token: "xoxb-secret-token-raw"
			},
			params: {
				raw: $raw_params,
				debug: true
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]

	# Should log sanitized payload after processing raw params when debug is enabled
	echo "$output" | grep -q "parse_payload:: input payload (sanitized):"
	# Token should be redacted, not present in original form
	echo "$output" | grep -qv "xoxb-secret-token-raw"
	echo "$output" | grep -q "[REDACTED]"
	# Raw params content should be present
	echo "$output" | grep -q "raw-channel"
}

@test "parse_payload:: sanitized payload logging works with params.from_file when debug enabled" {
	local file_params
	file_params=$(jq -n '{
		channel: "file-channel",
		blocks: [{
			section: {
				type: "text",
				text: { type: "plain_text", text: "File params test" }
			}
		}]
	}')

	local params_file
	params_file=$(mktemp "${BATS_TEST_TMPDIR}/payload-tests.params.XXXXXX")
	echo "$file_params" >"$params_file"

	local test_payload
	test_payload=$(jq -n \
		--arg params_file "$params_file" \
		'{
			source: {
				slack_bot_user_oauth_token: "xoxb-secret-token-file"
			},
			params: {
				from_file: $params_file,
				debug: true
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]

	# Should log sanitized payload after processing from_file when debug is enabled
	echo "$output" | grep -q "parse_payload:: input payload (sanitized):"
	# Token should be redacted, not present in original form
	echo "$output" | grep -qv "xoxb-secret-token-file"
	echo "$output" | grep -q "[REDACTED]"
	# File params content should be present
	echo "$output" | grep -q "file-channel"

	rm -f "$params_file"
}

@test "parse_payload:: debug logs original payload with params.raw before transformation" {
	local raw_params
	raw_params=$(jq -n '{
		channel: "raw-channel",
		blocks: [{
			section: {
				type: "text",
				text: { type: "plain_text", text: "Raw params test" }
			}
		}]
	}')

	local test_payload
	test_payload=$(jq -n \
		--arg raw_params "$(echo "$raw_params" | jq -c .)" \
		'{
			source: {
				slack_bot_user_oauth_token: "xoxb-secret-token-raw"
			},
			params: {
				raw: $raw_params,
				debug: true
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]

	# Should log sanitized payload BEFORE params.raw is processed
	# The logged payload should still contain "raw" showing original structure
	echo "$output" | grep -q "parse_payload:: input payload (sanitized):"
	echo "$output" | grep -q '"raw"'
	# Token should be redacted
	echo "$output" | grep -qv "xoxb-secret-token-raw"
	echo "$output" | grep -q "[REDACTED]"
}

@test "parse_payload:: debug logs original payload with params.from_file before transformation" {
	local file_params
	file_params=$(jq -n '{
		channel: "file-channel",
		blocks: [{
			section: {
				type: "text",
				text: { type: "plain_text", text: "File params test" }
			}
		}]
	}')

	local params_file
	params_file=$(mktemp "${BATS_TEST_TMPDIR}/payload-tests.params.XXXXXX")
	echo "$file_params" >"$params_file"

	local test_payload
	test_payload=$(jq -n \
		--arg params_file "$params_file" \
		'{
			source: {
				slack_bot_user_oauth_token: "xoxb-secret-token-file"
			},
			params: {
				from_file: $params_file,
				debug: true
			}
		}')

	echo "$test_payload" >"$TEST_PAYLOAD_FILE"

	run parse_payload "$TEST_PAYLOAD_FILE"
	[[ "$status" -eq 0 ]]

	# Should log sanitized payload BEFORE params.from_file is processed
	# The logged payload should still contain "from_file" showing original structure
	echo "$output" | grep -q "parse_payload:: input payload (sanitized):"
	echo "$output" | grep -q '"from_file"'
	# Token should be redacted
	echo "$output" | grep -qv "xoxb-secret-token-file"
	echo "$output" | grep -q "[REDACTED]"

	rm -f "$params_file"
}

########################################################
# _resolve_block_color
########################################################

@test "_resolve_block_color:: empty prints empty" {
	run _resolve_block_color ""
	[[ "$status" -eq 0 ]]
	[[ -z "$output" ]]
}

@test "_resolve_block_color:: hex passes through" {
	run _resolve_block_color "#aB12Cd"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "#aB12Cd" ]]
}

@test "_resolve_block_color:: danger maps to DANGER_COLOR" {
	run _resolve_block_color "danger"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "$DANGER_COLOR" ]]
}

@test "_resolve_block_color:: success maps to SUCCESS_COLOR" {
	run _resolve_block_color "success"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "$SUCCESS_COLOR" ]]
}

@test "_resolve_block_color:: warning maps to WARN_COLOR" {
	run _resolve_block_color "warning"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "$WARN_COLOR" ]]
}

@test "_resolve_block_color:: unknown maps to DANGER_COLOR" {
	run _resolve_block_color "not-a-known-name"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "$DANGER_COLOR" ]]
}

########################################################
# _extract_block_type_and_value
########################################################

@test "_extract_block_type_and_value:: fails on empty block_item" {
	run _extract_block_type_and_value ""
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "block_item is required"
}

@test "_extract_block_type_and_value:: type field format rich-text" {
	local json
	json=$(jq -n '{type:"rich-text", elements:[]}')

	if ! _extract_block_type_and_value "$json"; then
		return 1
	fi
	[[ "$_EXTRACT_BLOCK_TYPE" == "rich-text" ]]
	echo "$_EXTRACT_BLOCK_VALUE" | jq -e 'has("type") | not' >/dev/null
}

@test "_extract_block_type_and_value:: key-based format" {
	local json
	json=$(jq -n '{"rich-text": {elements: []}}')

	if ! _extract_block_type_and_value "$json"; then
		return 1
	fi
	[[ "$_EXTRACT_BLOCK_TYPE" == "rich-text" ]]
}

@test "_extract_block_type_and_value:: section infers type text from text field" {
	local json
	json=$(jq -n '{type:"section", text:{type:"plain_text", text:"x"}}')

	if ! _extract_block_type_and_value "$json"; then
		return 1
	fi
	[[ "$_EXTRACT_BLOCK_TYPE" == "section" ]]
	echo "$_EXTRACT_BLOCK_VALUE" | jq -e '.type == "text"' >/dev/null
}

@test "_extract_block_type_and_value:: section infers type fields from fields" {
	local json
	json=$(jq -n '{type:"section", fields:[]}')

	if ! _extract_block_type_and_value "$json"; then
		return 1
	fi
	echo "$_EXTRACT_BLOCK_VALUE" | jq -e '.type == "fields"' >/dev/null
}

@test "_extract_block_type_and_value:: reads color from type field format" {
	local json
	json=$(jq -n '{type:"section", color:"success", text:{type:"plain_text", text:"x"}}')

	if ! _extract_block_type_and_value "$json"; then
		return 1
	fi
	[[ "$_EXTRACT_BLOCK_COLOR" == "success" ]]
}

########################################################
# _validate_block_counts
########################################################

@test "_validate_block_counts:: empty arrays succeed" {
	local bf af
	bf=$(mktemp "$_SLACK_WORKSPACE/validate-bc-b.XXXXXX")
	af=$(mktemp "$_SLACK_WORKSPACE/validate-bc-a.XXXXXX")
	echo '[]' >"$bf"
	echo '[]' >"$af"

	run _validate_block_counts "$bf" "$af"
	[[ "$status" -eq 0 ]]
}

@test "_validate_block_counts:: fails when blocks exceed MAX_BLOCKS" {
	local bf af
	bf=$(mktemp "$_SLACK_WORKSPACE/validate-bc-b.XXXXXX")
	af=$(mktemp "$_SLACK_WORKSPACE/validate-bc-a.XXXXXX")
	jq -n '[range(51) | {type:"section", text:{type:"plain_text", text:"x"}}]' >"$bf"
	echo '[]' >"$af"

	run _validate_block_counts "$bf" "$af"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "block count"
}

@test "_validate_block_counts:: fails when attachments exceed MAX_ATTACHMENTS" {
	local bf af
	bf=$(mktemp "$_SLACK_WORKSPACE/validate-bc-b.XXXXXX")
	af=$(mktemp "$_SLACK_WORKSPACE/validate-bc-a.XXXXXX")
	echo '[]' >"$bf"
	jq -n '[range(21) | {color:"#FF0000", blocks:[{type:"section"}]}]' >"$af"

	run _validate_block_counts "$bf" "$af"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "attachment count"
}

@test "_validate_block_counts:: fails when combined block total exceeds MAX_BLOCKS" {
	local bf af
	bf=$(mktemp "$_SLACK_WORKSPACE/validate-bc-b.XXXXXX")
	af=$(mktemp "$_SLACK_WORKSPACE/validate-bc-a.XXXXXX")
	jq -n '[range(31) | {type:"section", text:{type:"plain_text", text:"x"}}]' >"$bf"
	jq -n '[range(20) | {color:"#FF0000", blocks:[{type:"section"}]}]' >"$af"

	run _validate_block_counts "$bf" "$af"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "total block count"
}

@test "_validate_block_counts:: fails when paths missing" {
	run _validate_block_counts "" "/tmp/x"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "required"
}

########################################################
# _validate_thread_replies
########################################################

@test "_validate_thread_replies:: empty input succeeds" {
	run _validate_thread_replies ""
	[[ "$status" -eq 0 ]]
}

@test "_validate_thread_replies:: null string succeeds" {
	run _validate_thread_replies "null"
	[[ "$status" -eq 0 ]]
}

@test "_validate_thread_replies:: not an array fails" {
	run _validate_thread_replies '"x"'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "thread.replies must be an array"
}

@test "_validate_thread_replies:: missing blocks fails" {
	local raw
	raw=$(jq -n '[{text: "no blocks"}]')

	run _validate_thread_replies "$raw"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "thread.replies\[0\].blocks"
}

@test "_validate_thread_replies:: empty blocks array fails" {
	local raw
	raw=$(jq -n '[{blocks: []}]')

	run _validate_thread_replies "$raw"
	[[ "$status" -eq 1 ]]
}

@test "_validate_thread_replies:: valid replies succeed" {
	local raw
	raw=$(jq -n '[{blocks: [{section: {type: "text", text: {type: "plain_text", text: "r"}}}]}]')

	run _validate_thread_replies "$raw"
	[[ "$status" -eq 0 ]]
}

########################################################
# _build_slack_payload
########################################################

@test "_build_slack_payload:: fails without channel for API delivery" {
	local bf af
	bf=$(mktemp "$_SLACK_WORKSPACE/bsl-b.XXXXXX")
	af=$(mktemp "$_SLACK_WORKSPACE/bsl-a.XXXXXX")
	echo '[]' >"$bf"
	echo '[]' >"$af"
	jq -n '{params:{}}' >"$TEST_PAYLOAD_FILE"
	INPUT_PAYLOAD="$TEST_PAYLOAD_FILE"
	export INPUT_PAYLOAD
	unset EPHEMERAL_USER
	unset DELIVERY_METHOD
	unset CHANNEL
	BLOCKS_FILE="$bf"
	ATTACHMENTS_FILE="$af"
	export BLOCKS_FILE ATTACHMENTS_FILE

	run _build_slack_payload "" "" ""
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "channel is required"
}

@test "_build_slack_payload:: webhook omits channel when empty" {
	local bf af
	bf=$(mktemp "$_SLACK_WORKSPACE/bsl-b.XXXXXX")
	af=$(mktemp "$_SLACK_WORKSPACE/bsl-a.XXXXXX")
	echo '[{"type":"section","text":{"type":"plain_text","text":"x"}}]' >"$bf"
	echo '[]' >"$af"
	jq -n '{params:{}}' >"$TEST_PAYLOAD_FILE"
	INPUT_PAYLOAD="$TEST_PAYLOAD_FILE"
	export INPUT_PAYLOAD
	unset EPHEMERAL_USER
	unset CHANNEL
	DELIVERY_METHOD="webhook"
	export DELIVERY_METHOD
	BLOCKS_FILE="$bf"
	ATTACHMENTS_FILE="$af"
	export BLOCKS_FILE ATTACHMENTS_FILE

	run _build_slack_payload "" "" ""
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e 'has("channel") | not' >/dev/null
	echo "$output" | jq -e '.blocks | length == 1' >/dev/null
}

@test "_build_slack_payload:: minimal payload with blocks" {
	local bf af
	bf=$(mktemp "$_SLACK_WORKSPACE/bsl-b.XXXXXX")
	af=$(mktemp "$_SLACK_WORKSPACE/bsl-a.XXXXXX")
	echo '[{"type":"section","text":{"type":"plain_text","text":"hi"}}]' >"$bf"
	echo '[]' >"$af"
	jq -n '{params:{}}' >"$TEST_PAYLOAD_FILE"
	INPUT_PAYLOAD="$TEST_PAYLOAD_FILE"
	export INPUT_PAYLOAD
	unset EPHEMERAL_USER
	unset DELIVERY_METHOD
	CHANNEL="C123"
	export CHANNEL
	BLOCKS_FILE="$bf"
	ATTACHMENTS_FILE="$af"
	export BLOCKS_FILE ATTACHMENTS_FILE

	run _build_slack_payload "" "" ""
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.channel == "C123"' >/dev/null
	echo "$output" | jq -e '.blocks | length == 1' >/dev/null
	echo "$output" | jq -e 'has("thread_ts") | not' >/dev/null
}

@test "_build_slack_payload:: includes thread_ts when set" {
	local bf af
	bf=$(mktemp "$_SLACK_WORKSPACE/bsl-b.XXXXXX")
	af=$(mktemp "$_SLACK_WORKSPACE/bsl-a.XXXXXX")
	echo '[]' >"$bf"
	echo '[]' >"$af"
	jq -n '{params:{}}' >"$TEST_PAYLOAD_FILE"
	INPUT_PAYLOAD="$TEST_PAYLOAD_FILE"
	export INPUT_PAYLOAD
	CHANNEL="C1"
	export CHANNEL
	BLOCKS_FILE="$bf"
	ATTACHMENTS_FILE="$af"
	export BLOCKS_FILE ATTACHMENTS_FILE

	run _build_slack_payload "1234567890.123456" "" ""
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.thread_ts == "1234567890.123456"' >/dev/null
}

@test "_build_slack_payload:: includes user when EPHEMERAL_USER set" {
	local bf af
	bf=$(mktemp "$_SLACK_WORKSPACE/bsl-b.XXXXXX")
	af=$(mktemp "$_SLACK_WORKSPACE/bsl-a.XXXXXX")
	echo '[]' >"$bf"
	echo '[]' >"$af"
	jq -n '{params:{}}' >"$TEST_PAYLOAD_FILE"
	INPUT_PAYLOAD="$TEST_PAYLOAD_FILE"
	export INPUT_PAYLOAD
	CHANNEL="C1"
	export CHANNEL
	EPHEMERAL_USER="U99"
	export EPHEMERAL_USER
	BLOCKS_FILE="$bf"
	ATTACHMENTS_FILE="$af"
	export BLOCKS_FILE ATTACHMENTS_FILE

	run _build_slack_payload "" "" ""
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.user == "U99"' >/dev/null
	unset EPHEMERAL_USER
}

@test "_build_slack_payload:: text over MAX_TEXT_LENGTH fails" {
	local bf af long_text
	bf=$(mktemp "$_SLACK_WORKSPACE/bsl-b.XXXXXX")
	af=$(mktemp "$_SLACK_WORKSPACE/bsl-a.XXXXXX")
	echo '[]' >"$bf"
	echo '[]' >"$af"
	long_text=$(awk 'BEGIN {for(i=0;i<40001;i++) printf "a"}')
	jq -n '{params:{}}' >"$TEST_PAYLOAD_FILE"
	INPUT_PAYLOAD="$TEST_PAYLOAD_FILE"
	export INPUT_PAYLOAD
	CHANNEL="C1"
	export CHANNEL
	BLOCKS_FILE="$bf"
	ATTACHMENTS_FILE="$af"
	export BLOCKS_FILE ATTACHMENTS_FILE

	run _build_slack_payload "" "$long_text" ""
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "text field length"
}

@test "_build_slack_payload:: thread_replies merged when non-empty" {
	local bf af raw
	bf=$(mktemp "$_SLACK_WORKSPACE/bsl-b.XXXXXX")
	af=$(mktemp "$_SLACK_WORKSPACE/bsl-a.XXXXXX")
	echo '[]' >"$bf"
	echo '[]' >"$af"
	jq -n '{params:{}}' >"$TEST_PAYLOAD_FILE"
	INPUT_PAYLOAD="$TEST_PAYLOAD_FILE"
	export INPUT_PAYLOAD
	CHANNEL="C1"
	export CHANNEL
	BLOCKS_FILE="$bf"
	ATTACHMENTS_FILE="$af"
	export BLOCKS_FILE ATTACHMENTS_FILE
	raw=$(jq -n '[{blocks: [{section: {type: "text", text: {type: "plain_text", text: "r"}}}]}]')

	run _build_slack_payload "" "" "$raw"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.thread_replies | length == 1' >/dev/null
}

########################################################
# _resolve_delivery_method
########################################################

@test "_resolve_delivery_method:: api when token in payload" {
	jq -n '{source:{slack_bot_user_oauth_token:"xoxb-payload"}}' >"$TEST_PAYLOAD_FILE"
	INPUT_PAYLOAD="$TEST_PAYLOAD_FILE"
	export INPUT_PAYLOAD
	unset SLACK_BOT_USER_OAUTH_TOKEN WEBHOOK_URL DELIVERY_METHOD

	if ! _resolve_delivery_method; then
		return 1
	fi
	[[ "$DELIVERY_METHOD" == "api" ]]
	[[ "$SLACK_BOT_USER_OAUTH_TOKEN" == "xoxb-payload" ]]
}

@test "_resolve_delivery_method:: webhook when webhook_url in payload" {
	jq -n '{source:{webhook_url:"https://hooks.slack.com/x"}}' >"$TEST_PAYLOAD_FILE"
	INPUT_PAYLOAD="$TEST_PAYLOAD_FILE"
	export INPUT_PAYLOAD
	unset SLACK_BOT_USER_OAUTH_TOKEN WEBHOOK_URL DELIVERY_METHOD

	if ! _resolve_delivery_method; then
		return 1
	fi
	[[ "$DELIVERY_METHOD" == "webhook" ]]
}

@test "_resolve_delivery_method:: fails when neither token nor webhook" {
	jq -n '{source:{}}' >"$TEST_PAYLOAD_FILE"
	INPUT_PAYLOAD="$TEST_PAYLOAD_FILE"
	export INPUT_PAYLOAD
	unset SLACK_BOT_USER_OAUTH_TOKEN WEBHOOK_URL DELIVERY_METHOD

	run _resolve_delivery_method
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "either source.slack_bot_user_oauth_token"
}

########################################################
# _resolve_channel
########################################################

@test "_resolve_channel:: api requires channel from env when missing in payload" {
	jq -n '{source:{slack_bot_user_oauth_token:"t"}, params:{}}' >"$TEST_PAYLOAD_FILE"
	INPUT_PAYLOAD="$TEST_PAYLOAD_FILE"
	export INPUT_PAYLOAD
	DELIVERY_METHOD="api"
	export DELIVERY_METHOD
	CHANNEL="C-from-env"
	export CHANNEL

	if ! _resolve_channel; then
		return 1
	fi
	[[ "$CHANNEL" == "C-from-env" ]]
}

@test "_resolve_channel:: api fails when channel missing everywhere" {
	jq -n '{source:{slack_bot_user_oauth_token:"t"}, params:{}}' >"$TEST_PAYLOAD_FILE"
	INPUT_PAYLOAD="$TEST_PAYLOAD_FILE"
	export INPUT_PAYLOAD
	DELIVERY_METHOD="api"
	export DELIVERY_METHOD
	unset CHANNEL

	run _resolve_channel
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "params.channel is required for API delivery"
}

@test "_resolve_channel:: webhook allows empty channel" {
	jq -n '{source:{webhook_url:"https://hooks.slack.com/x"}, params:{}}' >"$TEST_PAYLOAD_FILE"
	INPUT_PAYLOAD="$TEST_PAYLOAD_FILE"
	export INPUT_PAYLOAD
	DELIVERY_METHOD="webhook"
	export DELIVERY_METHOD
	unset CHANNEL

	if ! _resolve_channel; then
		return 1
	fi
}

########################################################
# _load_raw_params
########################################################

@test "_load_raw_params:: no-op when params.raw absent" {
	jq -n '{params:{channel:"x"}}' >"$TEST_PAYLOAD_FILE"
	INPUT_PAYLOAD="$TEST_PAYLOAD_FILE"
	export INPUT_PAYLOAD

	run _load_raw_params
	[[ "$status" -eq 0 ]]
	[[ "$(jq -r '.params.channel' "$TEST_PAYLOAD_FILE")" == "x" ]]
}

@test "_load_raw_params:: invalid JSON fails" {
	jq -n '{params:{raw:"not json"}}' >"$TEST_PAYLOAD_FILE"
	INPUT_PAYLOAD="$TEST_PAYLOAD_FILE"
	export INPUT_PAYLOAD

	run _load_raw_params
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "raw payload is not valid JSON"
}

@test "_load_raw_params:: valid raw replaces params" {
	local raw_compact
	raw_compact=$(jq -c -n '{channel:"raw-ch", blocks:[]}')

	jq -n --arg raw "$raw_compact" '{source:{slack_bot_user_oauth_token:"t"}, params:{raw:$raw}}' >"$TEST_PAYLOAD_FILE"
	INPUT_PAYLOAD="$TEST_PAYLOAD_FILE"
	export INPUT_PAYLOAD

	run _load_raw_params
	[[ "$status" -eq 0 ]]
	[[ "$(jq -r '.params.channel' "$TEST_PAYLOAD_FILE")" == "raw-ch" ]]
}

########################################################
# _load_from_file_params
########################################################

@test "_load_from_file_params:: no-op when from_file absent" {
	jq -n '{params:{channel:"x"}}' >"$TEST_PAYLOAD_FILE"
	INPUT_PAYLOAD="$TEST_PAYLOAD_FILE"
	export INPUT_PAYLOAD

	run _load_from_file_params
	[[ "$status" -eq 0 ]]
}

@test "_load_from_file_params:: fails when file missing" {
	jq -n '{params:{from_file:"/nonexistent/params.json"}}' >"$TEST_PAYLOAD_FILE"
	INPUT_PAYLOAD="$TEST_PAYLOAD_FILE"
	export INPUT_PAYLOAD

	run _load_from_file_params
	[[ "$status" -eq 1 ]]
}

@test "_load_from_file_params:: loads valid JSON file into params" {
	local pf
	pf=$(mktemp "$_SLACK_WORKSPACE/from-file-params.XXXXXX")
	jq -n '{channel:"file-ch", blocks:[]}' >"$pf"

	jq -n --arg f "$pf" '{source:{slack_bot_user_oauth_token:"t"}, params:{from_file:$f}}' >"$TEST_PAYLOAD_FILE"
	INPUT_PAYLOAD="$TEST_PAYLOAD_FILE"
	export INPUT_PAYLOAD

	run _load_from_file_params
	[[ "$status" -eq 0 ]]
	[[ "$(jq -r '.params.channel' "$TEST_PAYLOAD_FILE")" == "file-ch" ]]
	rm -f "$pf"
}
