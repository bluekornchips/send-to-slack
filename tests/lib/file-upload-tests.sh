#!/usr/bin/env bats
#
# Test file for file-upload.sh
#

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		echo "Failed to get git root" >&2
		exit 1
	fi

	SCRIPT="$GIT_ROOT/lib/file-upload.sh"
	SEND_TO_SLACK_SCRIPT="$GIT_ROOT/bin/send-to-slack.sh"

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

	TEST_FILE="$GIT_ROOT/test.txt"
	CHANNEL="test-channel"
	COMMENT="test comment"
	TITLE="test title"
	SLACK_BOT_USER_OAUTH_TOKEN="test-token"

	echo "Test file content" >"$TEST_FILE"

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
	large_file=$(mktemp file-upload-tests.large-file.XXXXXX)
	trap 'rm -f "$large_file" 2>/dev/null || true' EXIT
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
	trap - EXIT
}

@test "file_upload:: file size exactly at 1 GB limit succeeds" {
	# Create a mock file that reports exactly 1 GB
	local test_file
	test_file=$(mktemp file-upload-tests.test-file.XXXXXX)
	trap 'rm -f "$test_file" 2>/dev/null || true' EXIT
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
	trap - EXIT
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

teardown() {
	[[ -n "$TEST_FILE" ]] && rm -f "$TEST_FILE"
	[[ -n "$large_file" ]] && rm -f "$large_file"
	[[ -n "$test_file" ]] && rm -f "$test_file"
	return 0
}
