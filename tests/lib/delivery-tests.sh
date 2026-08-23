#!/usr/bin/env bats
#
# Tests for lib/delivery.sh
#

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		fail "Failed to get git root"
	fi

	LIB="$GIT_ROOT/lib/delivery.sh"
	if [[ ! -f "$LIB" ]]; then
		fail "Script not found: $LIB"
	fi

	export GIT_ROOT
	export LIB

	return 0
}

setup() {
	# shellcheck source=lib/loader.sh
	source "$GIT_ROOT/lib/loader.sh"
	# shellcheck source=lib/slack/api.sh
	source "$GIT_ROOT/lib/slack/api.sh"
	source "$LIB"
	unset RESPONSE
	unset DELIVERY_METHOD
	unset EPHEMERAL_USER

	return 0
}

@test "_response_field:: returns empty when RESPONSE is unset" {
	run _response_field ts
	[[ "$status" -eq 0 ]]
	[[ -z "$output" ]]
}

@test "_response_field:: extracts a string field" {
	RESPONSE=$(
		cat <<-'EOF'
			{
			  "ok": true,
			  "ts": "123.456",
			  "channel": "C123"
			}
		EOF
	)
	run _response_field ts
	[[ "$status" -eq 0 ]]
	[[ "$output" == "123.456" ]]
}

@test "_response_field:: treats JSON null as empty" {
	RESPONSE=$(
		cat <<-'EOF'
			{
			  "ts": null
			}
		EOF
	)
	run _response_field ts
	[[ "$status" -eq 0 ]]
	[[ -z "$output" ]]
}

@test "run_send_from_input:: fails when send_notification fails" {
	send_notification() {
		return 1
	}

	run run_send_from_input "/tmp/input.json" '{"text":"hi"}'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "failed to send notification"
}

@test "run_send_from_input:: skips replies and crosspost for webhook delivery" {
	send_notification() {
		return 0
	}
	send_thread_replies() {
		echo "send_thread_replies should not run" >&2
		return 1
	}
	crosspost_notification() {
		echo "crosspost_notification should not run" >&2
		return 1
	}
	DELIVERY_METHOD="webhook"

	run run_send_from_input "/tmp/input.json" '{"text":"hi"}'
	[[ "$status" -eq 0 ]]
	echo "$output" \
		grep -q "delivery method webhook does not support thread replies"
	echo "$output" | grep -q "delivery method webhook does not support crosspost"
}

@test "run_send_from_input:: skips replies and crosspost for ephemeral messages" {
	send_notification() {
		return 0
	}
	send_thread_replies() {
		echo "send_thread_replies should not run" >&2
		return 1
	}
	crosspost_notification() {
		echo "crosspost_notification should not run" >&2
		return 1
	}
	EPHEMERAL_USER="U123"

	run run_send_from_input "/tmp/input.json" '{"text":"hi"}'
	[[ "$status" -eq 0 ]]
	echo "$output" \
		grep -q "chat.postEphemeral does not support thread replies or crosspost"
}

@test "run_send_from_input:: continues when thread replies fail and fails on crosspost" {
	send_notification() {
		return 0
	}
	send_thread_replies() {
		return 1
	}
	crosspost_notification() {
		return 1
	}
	RESPONSE=$(
		cat <<-'EOF'
			{
			  "ts": "111.222"
			}
		EOF
	)

	run run_send_from_input "/tmp/input.json" '{"text":"hi"}'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "send_thread_replies encountered failures, continuing"
	echo "$output" | grep -q "failed to crosspost notification"
}

@test "run_send_from_input:: uses payload thread_ts when present" {
	local seen_file
	seen_file=$(mktemp "${BATS_TEST_TMPDIR}/delivery-thread-ts.XXXXXX")
	send_notification() {
		return 0
	}
	send_thread_replies() {
		printf '%s' "$2" >"$seen_file"
		return 0
	}
	crosspost_notification() {
		return 0
	}
	RESPONSE=$(
		cat <<-'EOF'
			{
			  "ts": "111.222"
			}
		EOF
	)

	run run_send_from_input "/tmp/input.json" '{"thread_ts":"999.000"}'
	[[ "$status" -eq 0 ]]
	[[ "$(cat "$seen_file")" == "999.000" ]]
}

@test "run_delivery_from_input:: sends when message_ts is absent" {
	local pf
	pf=$(mktemp "${BATS_TEST_TMPDIR}/delivery-send-path.XXXXXX")
	jq -n '{params: {channel: "#general"}}' >"$pf"
	send_notification() {
		return 0
	}
	send_thread_replies() {
		return 0
	}
	crosspost_notification() {
		return 0
	}

	run run_delivery_from_input "$pf" '{"text":"hello"}'
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "delivery:: sending notification"
	rm -f "$pf"
}

@test "_run_chat_update_from_input:: returns 1 when no message_ts" {
	local pf
	pf=$(mktemp "${BATS_TEST_TMPDIR}/delivery-ruci-no-ts.XXXXXX")
	jq -n '{params: {channel: "#general"}}' >"$pf"

	run _run_chat_update_from_input "$pf" '{"text":"hello"}'
	[[ "$status" -eq 1 ]]
	rm -f "$pf"
}

@test "_run_chat_update_from_input:: dry run succeeds with message_ts" {
	local pf
	pf=$(mktemp "${BATS_TEST_TMPDIR}/delivery-ruci-dry.XXXXXX")
	jq -n '{params: {channel: "#general", message_ts: "111.222"}}' >"$pf"
	DRY_RUN="true"
	export DRY_RUN

	run _run_chat_update_from_input "$pf" '{"text":"hello"}'
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "run_chat_update_from_input:: updating existing Slack message via chat.update"
	rm -f "$pf"
}

@test "_run_chat_update_from_input:: resolves channel before update when not dry run" {
	local pf
	pf=$(mktemp "${BATS_TEST_TMPDIR}/delivery-ruci-resolve.XXXXXX")
	jq -n '{params: {channel: "#general", message_ts: "111.222"}}' >"$pf"
	DRY_RUN="false"
	DELIVERY_METHOD="api"
	export DRY_RUN DELIVERY_METHOD

	resolve_channel_id() {
		echo "C999"
		return 0
	}
	update_message() {
		[[ "$1" == "C999" ]] || return 1
		return 0
	}

	run _run_chat_update_from_input "$pf" '{"text":"hello"}'
	[[ "$status" -eq 0 ]]
	rm -f "$pf"
}
