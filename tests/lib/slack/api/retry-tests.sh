#!/usr/bin/env bats
#
# Tests for lib/slack/api/retry.sh
#

load "api-test-helper.sh"

setup_file() {
	api_test_setup_file
	return 0
}

setup() {
	api_test_setup
	return 0
}

teardown() {
	api_test_teardown
	return 0
}

# retry_with_backoff
########################################################

@test "retry_with_backoff:: succeeds on first attempt" {
	local attempt_file
	attempt_file=$(mktemp \
		"${BATS_TEST_TMPDIR}/slack-api-tests.retry-attempt.XXXXXX")
	echo "0" >"$attempt_file"

	test_command() {
		local count
		count=$(cat "$attempt_file")
		count=$((count + 1))
		echo "$count" >"$attempt_file"
		return 0
	}
	export -f test_command
	export attempt_file

	run retry_with_backoff 3 test_command
	local attempt_count
	attempt_count=$(cat "$attempt_file")
	rm -f "$attempt_file"

	[[ "$status" -eq 0 ]]
	[[ $attempt_count -eq 1 ]]
}

@test "retry_with_backoff:: retries on failure and succeeds" {
	local attempt_file
	attempt_file=$(mktemp \
		"${BATS_TEST_TMPDIR}/slack-api-tests.retry-attempt.XXXXXX")
	echo "0" >"$attempt_file"

	test_command() {
		local count
		count=$(cat "$attempt_file")
		count=$((count + 1))
		echo "$count" >"$attempt_file"
		if [[ $count -lt 2 ]]; then
			return 1
		fi
		return 0
	}
	export -f test_command
	export attempt_file

	RETRY_INITIAL_DELAY=0
	export RETRY_INITIAL_DELAY

	run retry_with_backoff 3 test_command
	local attempt_count
	attempt_count=$(cat "$attempt_file")
	rm -f "$attempt_file"

	[[ "$status" -eq 0 ]]
	[[ $attempt_count -eq 2 ]]
}

@test "retry_with_backoff:: exhausts all retries on persistent failure" {
	local attempt_file
	attempt_file=$(mktemp \
		"${BATS_TEST_TMPDIR}/slack-api-tests.retry-attempt.XXXXXX")
	echo "0" >"$attempt_file"

	test_command() {
		local count
		count=$(cat "$attempt_file")
		count=$((count + 1))
		echo "$count" >"$attempt_file"
		return 1
	}
	export -f test_command
	export attempt_file

	RETRY_INITIAL_DELAY=0
	RETRY_MAX_ATTEMPTS=3
	export RETRY_INITIAL_DELAY
	export RETRY_MAX_ATTEMPTS

	run retry_with_backoff 3 test_command
	local attempt_count
	attempt_count=$(cat "$attempt_file")
	rm -f "$attempt_file"

	[[ "$status" -eq 1 ]]
	[[ $attempt_count -eq 3 ]]
	echo "$output" | grep -q "All 3 attempts failed"
}

@test "retry_with_backoff:: respects RETRY_MAX_ATTEMPTS" {
	local attempt_file
	attempt_file=$(mktemp \
		"${BATS_TEST_TMPDIR}/slack-api-tests.retry-attempt.XXXXXX")
	echo "0" >"$attempt_file"

	test_command() {
		local count
		count=$(cat "$attempt_file")
		count=$((count + 1))
		echo "$count" >"$attempt_file"
		return 1
	}
	export -f test_command
	export attempt_file

	RETRY_INITIAL_DELAY=0
	RETRY_MAX_ATTEMPTS=5
	export RETRY_INITIAL_DELAY
	export RETRY_MAX_ATTEMPTS

	run retry_with_backoff 5 test_command
	local attempt_count
	attempt_count=$(cat "$attempt_file")
	rm -f "$attempt_file"

	[[ "$status" -eq 1 ]]
	[[ $attempt_count -eq 5 ]]
}

@test "retry_with_backoff:: uses exponential backoff" {
	local attempt_file sleep_log
	attempt_file=$(mktemp \
		"${BATS_TEST_TMPDIR}/slack-api-tests.retry-attempt.XXXXXX")
	sleep_log=$(mktemp "${BATS_TEST_TMPDIR}/slack-api-tests.sleep-log.XXXXXX")
	echo "0" >"$attempt_file"

	test_command() {
		local count
		count=$(cat "$attempt_file")
		count=$((count + 1))
		echo "$count" >"$attempt_file"
		return 1
	}
	sleep() { echo "$1" >>"$sleep_log"; }
	export -f test_command
	export -f sleep
	export attempt_file
	export sleep_log

	RETRY_INITIAL_DELAY=1
	RETRY_BACKOFF_MULTIPLIER=2
	RETRY_MAX_ATTEMPTS=3
	export RETRY_INITIAL_DELAY
	export RETRY_BACKOFF_MULTIPLIER
	export RETRY_MAX_ATTEMPTS

	run retry_with_backoff 3 test_command
	rm -f "$attempt_file"

	[[ "$status" -eq 1 ]]
	# 3 attempts produce 2 inter-attempt sleeps: 1s then 2s
	[[ "$(sed -n '1p' "$sleep_log")" == "1" ]]
	[[ "$(sed -n '2p' "$sleep_log")" == "2" ]]
	rm -f "$sleep_log"
}

@test "retry_with_backoff:: respects RETRY_MAX_DELAY" {
	local attempt_file sleep_log
	attempt_file=$(mktemp \
		"${BATS_TEST_TMPDIR}/slack-api-tests.retry-attempt.XXXXXX")
	sleep_log=$(mktemp "${BATS_TEST_TMPDIR}/slack-api-tests.sleep-log.XXXXXX")
	echo "0" >"$attempt_file"

	test_command() {
		local count
		count=$(cat "$attempt_file")
		count=$((count + 1))
		echo "$count" >"$attempt_file"
		return 1
	}
	sleep() { echo "$1" >>"$sleep_log"; }
	export -f test_command
	export -f sleep
	export attempt_file
	export sleep_log

	RETRY_INITIAL_DELAY=2
	RETRY_BACKOFF_MULTIPLIER=10
	RETRY_MAX_DELAY=3
	RETRY_MAX_ATTEMPTS=3
	export RETRY_INITIAL_DELAY
	export RETRY_BACKOFF_MULTIPLIER
	export RETRY_MAX_DELAY
	export RETRY_MAX_ATTEMPTS

	run retry_with_backoff 3 test_command
	rm -f "$attempt_file"

	[[ "$status" -eq 1 ]]
	# 3 attempts produce 2 inter-attempt sleeps: 2s then min(20,3)=3s
	[[ "$(sed -n '1p' "$sleep_log")" == "2" ]]
	[[ "$(sed -n '2p' "$sleep_log")" == "3" ]]
	rm -f "$sleep_log"
}

@test "retry_with_backoff:: uses default RETRY_MAX_ATTEMPTS when not specified" {
	local attempt_file
	attempt_file=$(mktemp \
		"${BATS_TEST_TMPDIR}/slack-api-tests.retry-attempt.XXXXXX")
	echo "0" >"$attempt_file"

	test_command() {
		local count
		count=$(cat "$attempt_file")
		count=$((count + 1))
		echo "$count" >"$attempt_file"
		return 1
	}
	export -f test_command
	export attempt_file

	RETRY_MAX_ATTEMPTS=2
	RETRY_INITIAL_DELAY=0
	export RETRY_MAX_ATTEMPTS
	export RETRY_INITIAL_DELAY

	run retry_with_backoff "" test_command
	local attempt_count
	attempt_count=$(cat "$attempt_file")
	rm -f "$attempt_file"

	[[ "$status" -eq 1 ]]
	[[ $attempt_count -eq 2 ]]
}

########################################################
