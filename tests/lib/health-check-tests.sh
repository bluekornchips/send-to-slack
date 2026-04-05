#!/usr/bin/env bats
#
# Tests for lib/health-check.sh
#

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		fail "Failed to get git root"
	fi

	LIB="$GIT_ROOT/lib/health-check.sh"
	if [[ ! -f "$LIB" ]]; then
		fail "Script not found: $LIB"
	fi

	export GIT_ROOT
	export LIB

	return 0
}

setup() {
	source "$LIB"

	unset SLACK_BOT_USER_OAUTH_TOKEN
	unset DRY_RUN
	unset SKIP_SLACK_API_CHECK

	return 0
}

@test "health_check:: passes when dependencies are available" {
	run health_check
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "jq found"
	echo "$output" | grep -q "curl found"
	echo "$output" | grep -q "Health check passed"
}

@test "health_check:: skips API check when token not set" {
	run health_check
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "SLACK_BOT_USER_OAUTH_TOKEN not set, skipping API connectivity check"
}

@test "health_check:: skips Slack API request when DRY_RUN is true" {
	SLACK_BOT_USER_OAUTH_TOKEN="test-token"
	export SLACK_BOT_USER_OAUTH_TOKEN
	DRY_RUN="true"
	export DRY_RUN

	run health_check
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Testing Slack API connectivity"
	echo "$output" | grep -q "Slack API connectivity check skipped (DRY_RUN or SKIP_SLACK_API_CHECK set)"
}

@test "health_check:: calls Slack auth.test when token set and not dry run" {
	local mock_bin
	mock_bin="${BATS_TEST_TMPDIR}/health-check-mock-curl-bin"
	mkdir -p "$mock_bin"
	cat >"$mock_bin/curl" <<'EOF'
#!/usr/bin/env bash
out=""
while [[ $# -gt 0 ]]; do
	if [[ "$1" == "-o" ]]; then
		out="$2"
		shift 2
		continue
	fi
	shift
done
if [[ -n "$out" ]]; then
	printf '%s' '{"ok":true,"team":"mock-team","user":"mock-user"}' >"$out"
fi
printf '200'
EOF
	chmod +x "$mock_bin/curl"

	SLACK_BOT_USER_OAUTH_TOKEN="xoxb-test-mock"
	export SLACK_BOT_USER_OAUTH_TOKEN
	PATH="${mock_bin}:${PATH}"
	export PATH

	run health_check
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "Slack API accessible - Team: mock-team, User: mock-user"
}
