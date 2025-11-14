#!/usr/bin/env bats
#
# Test file for file-upload.sh
#
SMOKE_TEST=${SMOKE_TEST:-false}

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		echo "Failed to get git root" >&2
		exit 1
	fi

	SCRIPT="$GIT_ROOT/bin/file-upload.sh"
	SEND_TO_SLACK_SCRIPT="$GIT_ROOT/send-to-slack.sh"

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
	export SEND_TO_SLACK_SCRIPT
}

setup() {
	source "$SCRIPT"

	SEND_TO_SLACK_ROOT="$GIT_ROOT"

	TEST_FILE="$GIT_ROOT/test.txt"
	CHANNEL="test-channel"
	COMMENT="test comment"
	TITLE="test title"
	SLACK_BOT_USER_OAUTH_TOKEN="test-token"

	echo "Test file content" >"$TEST_FILE"

	export SEND_TO_SLACK_ROOT
	export TEST_FILE
	export CHANNEL
	export COMMENT
	export TITLE
	export SLACK_BOT_USER_OAUTH_TOKEN

	# Create JSON input for tests
	JSON_INPUT=$(jq -n \
		--arg path "$TEST_FILE" \
		--arg title "$TITLE" \
		--arg text "$COMMENT" \
		'{
			file: {
				path: $path,
				title: $title,
				text: $text
			}
		}')

	export JSON_INPUT

	return 0
}

########################################################
# mocks
########################################################

mock_get_upload_url_success() {
	_get_upload_url() {
		FILE_ID="test123"
		UPLOAD_URL="https://files.slack.com/upload/v1/test123"
		export FILE_ID
		export UPLOAD_URL
		return 0
	}
	return 0
}

mock_post_file_contents_success() {
	_post_file_contents() {
		echo "OK - $FILE_SIZE"
		return 0
	}
	return 0
}

mock_complete_upload_success() {
	_complete_upload() {
		echo '{"id": "test123", "name": "test.txt", "permalink": "https://test.slack.com/files/test123"}'
		return 0
	}
	return 0
}

########################################################
# _get_upload_url
########################################################

@test "_get_upload_url:: fails when curl returns error" {
	curl() {
		echo "failed to get upload URL"
		return 1
	}

	export -f curl

	run _get_upload_url
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "_get_upload_url:: failed to get upload URL:"
}

@test "_get_upload_url:: fails on invalid JSON response" {
	curl() {
		echo "not json"
		return 0
	}

	export -f curl

	run _get_upload_url
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "_get_upload_url:: invalid JSON response from Slack API"
}

@test "_get_upload_url:: fails when Slack API returns ok=false" {
	curl() {
		echo '{"ok": false}'
		return 0
	}

	export -f curl

	run _get_upload_url
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "_get_upload_url:: Slack API error:"
}

@test "_get_upload_url:: fails when upload URL is missing in response" {
	curl() {
		echo '{"ok": true}'
		return 0
	}

	export -f curl

	run _get_upload_url
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "_get_upload_url:: missing upload URL in Slack response"
}

########################################################
# _post_file_contents
########################################################

@test "_post_file_contents:: fails on HTTP error 400" {
	curl() {
		printf "error response\n400"
		return 0
	}

	export -f curl

	run _post_file_contents
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "_post_file_contents:: HTTP error 400 from upload URL"
}

@test "_post_file_contents:: fails on unexpected response format" {
	curl() {
		printf "not ok\n200"
		return 0
	}

	export -f curl

	run _post_file_contents
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "_post_file_contents:: unexpected response format from upload URL"
}

@test "_post_file_contents:: fails on file size mismatch" {
	curl() {
		printf "OK - 100\n200"
		return 0
	}

	export -f curl

	run _post_file_contents
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "_post_file_contents:: file size mismatch"
}

########################################################
# file_upload
########################################################

@test "file_upload:: file not set" {
	run file_upload <<<'{}'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "file_upload:: file.path is required"
}

@test "file_upload:: file not found" {
	local json_input
	json_input=$(jq -n '{file: {path: "nonexistent.txt"}}')
	run file_upload <<<"$json_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "file_upload:: file not found: nonexistent.txt"
}

@test "file_upload:: channel not set" {
	unset CHANNEL

	run file_upload <<<"$JSON_INPUT"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "file_upload:: CHANNEL environment variable is required"
}

@test "file_upload:: text defaults to filename when empty" {
	local json_input
	json_input=$(jq -n --arg path "$TEST_FILE" '{file: {path: $path}}')

	_get_upload_url() {
		FILE_ID="test123"
		UPLOAD_URL="https://files.slack.com/upload/v1/test123"
		export FILE_ID
		export UPLOAD_URL
		return 0
	}

	_post_file_contents() {
		echo "OK - $FILE_SIZE"
		return 0
	}

	_complete_upload() {
		echo '{"id": "test123", "name": "test.txt", "permalink": "https://test.slack.com/files/test123"}'
		return 0
	}

	export -f _get_upload_url
	export -f _post_file_contents
	export -f _complete_upload

	run file_upload <<<"$json_input"
	[[ "$status" -eq 0 ]]
	# Should output rich_text block with file link
	echo "$output" | grep -q '"type": "rich_text"'
	echo "$output" | grep -q '"text": "test.txt"'
	echo "$output" | grep -q '"url": "https://test.slack.com/files/test123"'
}

@test "file_upload:: title defaults to basename when not set" {
	local json_input
	json_input=$(jq -n --arg path "$TEST_FILE" '{file: {path: $path}}')
	mock_get_upload_url_success
	mock_post_file_contents_success

	# Mock _complete_upload
	_complete_upload() {
		echo '{"id": "test123", "name": "test.txt", "permalink": "https://test.slack.com/files/test123"}'
		return 0
	}

	export -f _complete_upload

	run file_upload <<<"$json_input"
	[[ "$status" -eq 0 ]]
}

@test "file_upload:: slack bot user oauth token not set" {
	unset SLACK_BOT_USER_OAUTH_TOKEN

	run file_upload <<<"$JSON_INPUT"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "file_upload:: SLACK_BOT_USER_OAUTH_TOKEN environment variable is required"
}

@test "file_upload:: unable to determine file size" {
	stat() {
		return 1
	}

	export -f stat

	run file_upload <<<"$JSON_INPUT"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "file_upload:: unable to determine file size"
}

@test "file_upload:: file size exceeds 1 GB limit" {
	# Create a mock file that reports a size exceeding 1 GB
	local large_file
	large_file=$(mktemp)
	echo "test content" >"$large_file"

	# Mock stat to return a size exceeding 1 GB (1 GB + 1 byte)
	local oversized=$((1024 * 1024 * 1024 + 1))
	stat() {
		if [[ "$1" == "-c%s" ]] || [[ "$1" == "-f%z" ]]; then
			echo "$oversized"
			return 0
		fi
		command stat "$@"
	}

	export -f stat

	local json_input
	json_input=$(jq -n --arg path "$large_file" '{file: {path: $path}}')

	run file_upload <<<"$json_input"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "file_upload:: file size.*exceeds Slack's maximum"

	rm -f "$large_file"
}

@test "file_upload:: file size exactly at 1 GB limit succeeds" {
	# Create a mock file that reports exactly 1 GB
	local test_file
	test_file=$(mktemp)
	echo "test content" >"$test_file"

	# Mock stat to return exactly 1 GB
	local max_size=$((1024 * 1024 * 1024))
	stat() {
		if [[ "$1" == "-c%s" ]] || [[ "$1" == "-f%z" ]]; then
			echo "$max_size"
			return 0
		fi
		command stat "$@"
	}

	export -f stat

	mock_get_upload_url_success
	mock_post_file_contents_success
	mock_complete_upload_success

	local json_input
	json_input=$(jq -n --arg path "$test_file" '{file: {path: $path}}')

	run file_upload <<<"$json_input"
	[[ "$status" -eq 0 ]]

	rm -f "$test_file"
}

@test "file_upload:: fails when _get_upload_url fails" {
	_get_upload_url() {
		echo "_get_upload_url:: failed to get upload URL: " >&2
		return 1
	}

	export -f _get_upload_url

	run file_upload <<<"$JSON_INPUT"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "_get_upload_url:: failed to get upload URL:"
}

@test "file_upload:: fails when _post_file_contents fails" {
	mock_get_upload_url_success

	_post_file_contents() {
		echo "_post_file_contents:: failed to post file contents: " >&2
		return 1
	}

	export -f _post_file_contents

	run file_upload <<<"$JSON_INPUT"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "_post_file_contents:: failed to post file contents:"
}

########################################################
# smoke tests
########################################################

smoke_test_setup() {
	local blocks_json="$1"

	if [[ "$SMOKE_TEST" != "true" ]]; then
		skip "SMOKE_TEST is not set"
	fi

	if [[ -z "$REAL_TOKEN" ]]; then
		skip "SLACK_BOT_USER_OAUTH_TOKEN not set"
	fi

	CHANNEL="notification-testing"
	SLACK_BOT_USER_OAUTH_TOKEN="$REAL_TOKEN"
	DRY_RUN="false"

	source "$GIT_ROOT/bin/parse-payload.sh"
	source "$SEND_TO_SLACK_SCRIPT"

	SMOKE_TEST_PAYLOAD_FILE=$(mktemp)

	jq -n \
		--arg channel "$CHANNEL" \
		--arg dry_run "$DRY_RUN" \
		--argjson blocks "$blocks_json" \
		--arg token "$REAL_TOKEN" \
		'{
			source: {
				slack_bot_user_oauth_token: $token
			},
			params: {
				channel: $channel,
				blocks: $blocks,
				dry_run: $dry_run
			}
		}' >"$SMOKE_TEST_PAYLOAD_FILE"

	export SMOKE_TEST_PAYLOAD_FILE
}

teardown() {
	if [[ -f "$TEST_FILE" ]]; then
		rm -f "$TEST_FILE"
	fi
	[[ -n "$SMOKE_TEST_PAYLOAD_FILE" ]] && rm -f "$SMOKE_TEST_PAYLOAD_FILE"
	return 0
}

@test "smoke test, uploads hello world file" {
	local hello_world_file
	hello_world_file=$(mktemp)
	echo "hello world" >"$hello_world_file"

	local blocks_json
	blocks_json=$(jq -n --arg path "$hello_world_file" '[{ "file": { "path": $path } }]')

	smoke_test_setup "$blocks_json"

	if ! parse_payload "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		rm -f "$hello_world_file"
		return 1
	fi

	if [[ -z "$PAYLOAD" ]]; then
		echo "PAYLOAD is not set" >&2
		rm -f "$hello_world_file"
		return 1
	fi

	run send_notification
	local test_result=$status

	rm -f "$hello_world_file"

	[[ "$test_result" -eq 0 ]]
}

@test "smoke test, downloads Slack logo PNG and uploads it" {
	local slack_logo_file
	slack_logo_file=$(mktemp --suffix=".png")

	# Download the Slack developers logo PNG
	if ! curl -s -o "$slack_logo_file" "https://docs.slack.dev/img/logos/slack-developers-white.png"; then
		echo "Failed to download Slack logo PNG" >&2
		rm -f "$slack_logo_file"
		return 1
	fi

	# Verify the file was downloaded and has content
	if [[ ! -s "$slack_logo_file" ]]; then
		echo "Downloaded Slack logo PNG is empty" >&2
		rm -f "$slack_logo_file"
		return 1
	fi

	local blocks_json
	blocks_json=$(jq -n --arg path "$slack_logo_file" '[{ "file": { "path": $path, "title": "Slack Developers Logo" } }]')

	smoke_test_setup "$blocks_json"

	if ! parse_payload "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		rm -f "$slack_logo_file"
		return 1
	fi

	if [[ -z "$PAYLOAD" ]]; then
		echo "PAYLOAD is not set" >&2
		rm -f "$slack_logo_file"
		return 1
	fi

	run send_notification
	local test_result=$status

	# Clean up the downloaded file
	rm -f "$slack_logo_file"

	[[ "$test_result" -eq 0 ]]
}

@test "smoke test, multiple file blocks in blocks array" {
	local file1
	local file2
	file1=$(mktemp)
	file2=$(mktemp)
	echo "File 1 content" >"$file1"
	echo "File 2 content" >"$file2"

	local blocks_json
	blocks_json=$(jq -n \
		--arg path1 "$file1" \
		--arg path2 "$file2" \
		'[
			{ "file": { "path": $path1, "title": "First File" } },
			{ "file": { "path": $path2, "title": "Second File" } }
		]')

	smoke_test_setup "$blocks_json"

	if ! parse_payload "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		rm -f "$file1" "$file2"
		return 1
	fi

	if [[ -z "$PAYLOAD" ]]; then
		echo "PAYLOAD is not set" >&2
		rm -f "$file1" "$file2"
		return 1
	fi

	run send_notification
	local test_result=$status

	rm -f "$file1" "$file2"

	[[ "$test_result" -eq 0 ]]
}

@test "smoke test, file block without title uses filename" {
	local test_file
	test_file=$(mktemp --suffix=".txt")
	echo "Test content" >"$test_file"

	local blocks_json
	blocks_json=$(jq -n --arg path "$test_file" '[{ "file": { "path": $path } }]')

	smoke_test_setup "$blocks_json"

	if ! parse_payload "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		rm -f "$test_file"
		return 1
	fi

	if [[ -z "$PAYLOAD" ]]; then
		echo "PAYLOAD is not set" >&2
		rm -f "$test_file"
		return 1
	fi

	run send_notification
	local test_result=$status

	# Clean up
	rm -f "$test_file"

	[[ "$test_result" -eq 0 ]]
}

@test "smoke test, file block mixed with other blocks" {
	local test_file
	test_file=$(mktemp)
	echo "Report content" >"$test_file"

	local blocks_json
	blocks_json=$(jq -n \
		--arg path "$test_file" \
		'[
			{ "header": { "text": { "type": "plain_text", "text": "Report" } } },
			{ "section": { "type": "text", "text": { "type": "mrkdwn", "text": "See attached file" } } },
			{ "file": { "path": $path, "title": "Report File" } },
			{ "context": { "elements": [{ "type": "plain_text", "text": "Generated by CI" }] } }
		]')

	smoke_test_setup "$blocks_json"

	if ! parse_payload "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		rm -f "$test_file"
		return 1
	fi

	if [[ -z "$PAYLOAD" ]]; then
		echo "PAYLOAD is not set" >&2
		rm -f "$test_file"
		return 1
	fi

	run send_notification
	local test_result=$status

	# Clean up
	rm -f "$test_file"

	[[ "$test_result" -eq 0 ]]
}

@test "smoke test, file permissions debug after upload" {
	local test_file
	test_file=$(mktemp --suffix=".txt")
	echo "Permission test content" >"$test_file"

	chmod 644 "$test_file"

	local initial_perms
	initial_perms=$(stat -c "%a %A" "$test_file" 2>/dev/null || stat -f "%OLp %Sp" "$test_file" 2>/dev/null || echo "unknown")
	echo "Initial file permissions: $initial_perms" >&2

	local blocks_json
	blocks_json=$(jq -n --arg path "$test_file" '[{ "file": { "path": $path, "title": "Permission Test File" } }]')

	smoke_test_setup "$blocks_json"

	if ! parse_payload "$SMOKE_TEST_PAYLOAD_FILE"; then
		echo "parse_payload failed" >&2
		rm -f "$test_file"
		return 1
	fi

	if [[ -z "$PAYLOAD" ]]; then
		echo "PAYLOAD is not set" >&2
		rm -f "$test_file"
		return 1
	fi

	# Permission logs go to stderr, so they'll be visible in test output but may not be captured in $output variable because why not
	run send_notification
	local test_result=$status

	local final_perms
	final_perms=$(stat -c "%a %A" "$test_file" 2>/dev/null || stat -f "%OLp %Sp" "$test_file" 2>/dev/null || echo "unknown")
	echo "Final file permissions: $final_perms" >&2

	# Verify permissions haven't changed
	[[ "$initial_perms" == "$final_perms" ]]

	# Verify file still exists and is readable
	[[ -f "$test_file" ]]
	[[ -r "$test_file" ]]

	local file_content
	file_content=$(cat "$test_file")
	[[ "$file_content" == "Permission test content" ]]

	local file_readable
	local file_size
	file_readable=$([ -r "$test_file" ] && echo "yes" || echo "no")
	file_size=$(stat -c%s "$test_file" 2>/dev/null || stat -f%z "$test_file" 2>/dev/null)
	cat >&2 <<-EOF
		Permission debug summary:
			Initial: $initial_perms
			Final: $final_perms
			File readable: $file_readable
			File size: $file_size bytes
	EOF

	rm -f "$test_file"

	[[ "$test_result" -eq 0 ]]
}
