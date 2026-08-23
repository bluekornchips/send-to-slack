#!/usr/bin/env bash
#
# Tests for lib/cli.sh
#

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		fail "Failed to get git root"
	fi

	LIB="$GIT_ROOT/lib/cli.sh"
	if [[ ! -f "$LIB" ]]; then
		fail "Script not found: $LIB"
	fi

	export GIT_ROOT
	export LIB

	return 0
}

setup() {
	source "$GIT_ROOT/lib/get-version.sh"
	source "$LIB"

	unset SEND_TO_SLACK_CLI_INPUT_FILE
	health_check_mode=false

	return 0
}

@test "usage:: prints options and help text" {
	run usage
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Usage: send-to-slack"
	echo "$output" | grep -q -- "-h, --help"
	echo "$output" | grep -q -- "--health-check"
}

@test "parse_main_args:: help returns 2" {
	run parse_main_args "$GIT_ROOT" -h
	[[ "$status" -eq 2 ]]
	echo "$output" | grep -q "Usage: send-to-slack"
}

@test "parse_main_args:: version returns 2 and prints version" {
	run parse_main_args "$GIT_ROOT" --version
	[[ "$status" -eq 2 ]]
	echo "$output" | grep -q "send-to-slack,"
	echo "$output" | grep -q "version:"
	echo "$output" | grep -q "commit:"
}

@test "parse_main_args:: version fails when root_dir is empty" {
	run parse_main_args "" -v
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "root directory is required"
}

@test "parse_main_args:: unknown option returns 1" {
	run parse_main_args "$GIT_ROOT" --not-a-flag
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "unknown option"
}

@test "parse_main_args:: --file without path returns 1" {
	run parse_main_args "$GIT_ROOT" --file
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "requires a file path argument"
}

@test "parse_main_args:: --file cannot be specified twice" {
	run parse_main_args "$GIT_ROOT" --file /tmp/a.json --file /tmp/b.json
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "can only be specified once"
}

@test "parse_main_args:: --file sets SEND_TO_SLACK_CLI_INPUT_FILE" {
	if ! parse_main_args "$GIT_ROOT" --file /tmp/payload.json; then
		return 1
	fi
	[[ "$SEND_TO_SLACK_CLI_INPUT_FILE" == "/tmp/payload.json" ]]
}

@test "parse_main_args:: --health-check sets health_check_mode" {
	if ! parse_main_args "$GIT_ROOT" --health-check; then
		return 1
	fi
	[[ "$health_check_mode" == "true" ]]
}
