#!/usr/bin/env bats
#
# Test file for file-upload.sh
#

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		fail "Failed to get git root"
	fi

	SCRIPT="$GIT_ROOT/lib/slack/utils/file-upload.sh"
	SEND_TO_SLACK_SCRIPT="$GIT_ROOT/bin/send-to-slack.sh"

	if [[ ! -f "$SCRIPT" ]]; then
		fail "Script not found: $SCRIPT"
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

	_SLACK_WORKSPACE=$(mktemp -d "${BATS_TEST_TMPDIR}/file-upload-tests.workspace.XXXXXX")
	export _SLACK_WORKSPACE

	TEST_FILE="${BATS_TEST_TMPDIR}/file-upload-tests.test.txt"
	CHANNEL="test-channel"
	TITLE="test title"
	SLACK_BOT_USER_OAUTH_TOKEN="test-token"

	echo "Test file content" >"$TEST_FILE"

	export TEST_FILE
	export CHANNEL
	export TITLE
	export SLACK_BOT_USER_OAUTH_TOKEN

	JSON_INPUT=$(jq -n \
		--arg path "$TEST_FILE" \
		--arg title "$TITLE" \
		'{
			file: {
				path: $path,
				title: $title
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

@test "file_upload:: outputs metadata json with id title and name" {
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

	export -f _get_upload_url
	export -f _post_file_contents

	run file_upload <<<"$json_input"
	[[ "$status" -eq 0 ]]
	local meta
	meta=$(echo "$output" | grep -E '^\{')
	echo "$meta" | jq -e '.id == "test123"' >/dev/null
	echo "$meta" | jq -e --arg name "$(basename "$TEST_FILE")" \
		'.name == $name' >/dev/null
	echo "$meta" | jq -e --arg name "$(basename "$TEST_FILE")" \
		'.title == $name' >/dev/null
	! echo "$output" | grep -q '"type": "rich_text"'
}

@test "file_upload:: title defaults to basename when not set" {
	local json_input
	json_input=$(jq -n --arg path "$TEST_FILE" '{file: {path: $path}}')
	mock_get_upload_url_success
	mock_post_file_contents_success

	run file_upload <<<"$json_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -E '^\{' | jq -e --arg name "$(basename "$TEST_FILE")" \
		'.title == $name' >/dev/null
}

@test "file_upload:: dry-run skips Slack HTTP and prints placeholder id" {
	DRY_RUN="true"
	export DRY_RUN

	curl() {
		echo "curl should not be called in dry-run" >&2
		return 1
	}
	export -f curl

	run file_upload <<<"$JSON_INPUT"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "DRY_RUN enabled"
	echo "$output" | grep -E '^\{' | jq -e '.id == "F-DRY-RUN"' >/dev/null
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
	large_file=$(mktemp "${BATS_TEST_TMPDIR}/file-upload-tests.large-file.XXXXXX")
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
	echo "$output" | grep -q "file_upload:: file permissions"

	unset -f stat
	rm -f "$large_file"
}

@test "file_upload:: file size exactly at 1 GB limit succeeds" {
	# Create a mock file that reports exactly 1 GB
	local test_file
	test_file=$(mktemp "${BATS_TEST_TMPDIR}/file-upload-tests.test-file.XXXXXX")
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

	local json_input
	json_input=$(jq -n --arg path "$test_file" '{file: {path: $path}}')

	run file_upload <<<"$json_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -E '^\{' | jq -e '.id == "test123"' >/dev/null

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

# validate_file_path glob expansion
@test "validate_file_path:: resolves a glob pattern to a single matching file" {
	local glob_dir
	local glob_file

	glob_dir=$(mktemp -d "${BATS_TEST_TMPDIR}/glob-test.XXXXXX")
	glob_file="${glob_dir}/report_20260314_120000.txt"
	echo "timestamped content" >"${glob_file}"

	FILE_PATH="${glob_dir}/report_*.txt"
	export FILE_PATH

	validate_file_path

	[[ "$FILE_PATH" == "${glob_file}" ]]
}

@test "validate_file_path:: fails when glob matches no files" {
	local glob_dir

	glob_dir=$(mktemp -d "${BATS_TEST_TMPDIR}/glob-test.XXXXXX")

	FILE_PATH="${glob_dir}/report_*.txt"
	export FILE_PATH

	run validate_file_path

	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "file not found"
}

@test "validate_file_path:: fails when glob matches multiple files" {
	local glob_dir

	glob_dir=$(mktemp -d "${BATS_TEST_TMPDIR}/glob-test.XXXXXX")
	echo "a" >"${glob_dir}/report_001.txt"
	echo "b" >"${glob_dir}/report_002.txt"

	FILE_PATH="${glob_dir}/report_*.txt"
	export FILE_PATH

	run validate_file_path

	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "glob matched"
}

########################################################
# _get_upload_url snippet_type
########################################################

@test "_get_upload_url:: md filename sends snippet_type markdown" {
	local arg_capture
	arg_capture=$(mktemp "${BATS_TEST_TMPDIR}/file-upload-tests.curl-args.XXXXXX")
	export arg_capture

	FILENAME="pipeline.md"
	FILE_SIZE="12"
	export FILENAME
	export FILE_SIZE

	curl() {
		printf '%s\n' "$*" >"$arg_capture"
		echo '{"ok": true, "upload_url": "https://files.slack.com/upload/v1/x", "file_id": "F1"}'
		return 0
	}
	export -f curl

	run _get_upload_url
	[[ "$status" -eq 0 ]]
	grep -q "snippet_type=markdown" "$arg_capture"
	grep -q "files.getUploadURLExternal" "$arg_capture"
}

@test "_get_upload_url:: txt filename omits snippet_type" {
	local arg_capture
	arg_capture=$(mktemp "${BATS_TEST_TMPDIR}/file-upload-tests.curl-args.XXXXXX")
	export arg_capture

	FILENAME="notes.txt"
	FILE_SIZE="12"
	export FILENAME
	export FILE_SIZE

	curl() {
		printf '%s\n' "$*" >"$arg_capture"
		echo '{"ok": true, "upload_url": "https://files.slack.com/upload/v1/x", "file_id": "F1"}'
		return 0
	}
	export -f curl

	run _get_upload_url
	[[ "$status" -eq 0 ]]
	! grep -q "snippet_type=" "$arg_capture"
}

########################################################
# _complete_upload / share_uploaded_files
########################################################

@test "_complete_upload:: puts channel_id in form body not query string" {
	local arg_capture
	arg_capture=$(mktemp "${BATS_TEST_TMPDIR}/file-upload-tests.complete-args.XXXXXX")
	export arg_capture

	curl() {
		printf '%s\n' "$*" >"$arg_capture"
		echo '{"ok": true, "files": [{"id": "F1"}]}'
		return 0
	}
	export -f curl

	run _complete_upload '[{"id":"F1","title":"t"}]' "C1234567890"
	[[ "$status" -eq 0 ]]
	grep -q "channel_id=C1234567890" "$arg_capture"
	grep -q "files.completeUploadExternal" "$arg_capture"
	! grep -q "completeUploadExternal?channel_id=" "$arg_capture"
	! grep -q "initial_comment" "$arg_capture"
}

@test "_complete_upload:: sends blocks and omits them when empty" {
	local arg_capture
	arg_capture=$(mktemp "${BATS_TEST_TMPDIR}/file-upload-tests.complete-blocks.XXXXXX")
	export arg_capture

	curl() {
		printf '%s\n' "$*" >"$arg_capture"
		echo '{"ok": true, "files": [{"id": "F1"}]}'
		return 0
	}
	export -f curl

	run _complete_upload '[{"id":"F1","title":"t"}]' "C1234567890" \
		'[{"type":"context"}]'
	[[ "$status" -eq 0 ]]
	grep -q "blocks=" "$arg_capture"

	run _complete_upload '[{"id":"F1","title":"t"}]' "C1234567890" "[]"
	[[ "$status" -eq 0 ]]
	! grep -q "blocks=" "$arg_capture"
}

@test "share_uploaded_files:: requires payload channel" {
	resolve_channel_id() {
		echo "C1234567890"
		return 0
	}

	run share_uploaded_files '{"files":[{"id":"F1","title":"t"}]}'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "payload.channel is required"
}

@test "share_uploaded_files:: shares with resolved channel and sibling blocks" {
	local arg_capture
	arg_capture=$(mktemp "${BATS_TEST_TMPDIR}/file-upload-tests.share-args.XXXXXX")
	export arg_capture

	resolve_channel_id() {
		echo "C1234567890"
		return 0
	}

	curl() {
		printf '%s\n' "$*" >"$arg_capture"
		echo '{"ok": true, "files": [{"id": "F1", "shares": {"public": {"C1234567890": [{"ts": "1.2"}]}}}]}'
		return 0
	}
	export -f curl

	local payload
	payload=$(jq -n '{
		channel: "alerts",
		blocks: [{type: "context", elements: [{type: "mrkdwn", text: "author"}]}],
		files: [{id: "F1", title: "report.md", name: "report.md"}]
	}')

	run share_uploaded_files "$payload"
	[[ "$status" -eq 0 ]]
	grep -q "channel_id=C1234567890" "$arg_capture"
	grep -q "blocks=" "$arg_capture"
	! grep -q "initial_comment" "$arg_capture"
	! grep -q "chat.postMessage" "$arg_capture"
}

teardown() {
	rm -rf "$_SLACK_WORKSPACE"
	[[ -n "$TEST_FILE" ]] && rm -f "$TEST_FILE"
	return 0
}
