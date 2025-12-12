#!/usr/bin/env bats
#
# Test file for out.sh
#
GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
SCRIPT="$GIT_ROOT/concourse/resource-type/scripts/out.sh"
[[ ! -f "$SCRIPT" ]] && echo "Script not found: $SCRIPT" >&2 && return 1

setup() {
	SEND_TO_SLACK_SCRIPT="$(mktemp -t out-tests.send-to-slack.XXXXXX)"

	export SEND_TO_SLACK_SCRIPT

	return 0
}

teardown() {
	[[ -f "${SEND_TO_SLACK_SCRIPT:-}" ]] && rm -f "${SEND_TO_SLACK_SCRIPT}"
	return 0
}

########################################################
# Mocks
########################################################
mock_send_to_slack_success() {
	cat <<EOF >"${SEND_TO_SLACK_SCRIPT}"
#!/usr/bin/env bash
echo '{"version": {"timestamp": "2023-12-01T12:00:00Z"}, "metadata": [{"name": "dry_run", "value": "false"}]}'
EOF
	chmod 755 "${SEND_TO_SLACK_SCRIPT}"
}

mock_send_to_slack_failure() {
	cat <<EOF >"${SEND_TO_SLACK_SCRIPT}"
#!/usr/bin/env bash
echo "Failed to send message to Slack" >&2
exit 1
EOF
	chmod 755 "${SEND_TO_SLACK_SCRIPT}"
}

########################################################
# main
########################################################
@test "main:: successfully sends message" {
	mock_send_to_slack_success

	run "$SCRIPT" <<<"{}"

	[[ "$status" -eq 0 ]]
	echo "${output}" | grep -q "version"
	echo "${output}" | grep -q "timestamp"
	echo "${output}" | grep -q "metadata"
}

@test "main:: outputs correct JSON format with version and metadata" {
	mock_send_to_slack_success

	run "$SCRIPT" <<<"{}"

	[[ "$status" -eq 0 ]]

	if ! echo "${output}" | jq . >/dev/null 2>&1; then
		return 1
	fi

	local timestamp
	local metadata
	timestamp=$(echo "${output}" | jq -r '.version.timestamp')
	[[ -n "${timestamp}" ]]

	metadata=$(echo "${output}" | jq -r '.metadata')
	[[ "${metadata}" != "null" ]]
}

@test "main:: outputs failure message when send-to-slack.sh fails" {
	mock_send_to_slack_failure

	run "$SCRIPT" <<<"{}"

	[[ "$status" -eq 1 ]]
	echo "${output}" | grep -q "Failed to send message to Slack"
}
