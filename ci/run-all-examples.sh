#!/usr/bin/env bash
#
# Starts a local Concourse environment, loads all example pipelines,
# and triggers every job in every pipeline in order, waiting for each to finish.
#
# Required environment variables:
#   SLACK_BOT_USER_OAUTH_TOKEN  Slack bot token for pipeline variables
#   CHANNEL                     Primary Slack channel for pipeline variables
#
# Optional environment variables:
#   SIDE_CHANNEL       Secondary Slack channel, defaults to empty
#   SLACK_WEBHOOK_URL  Incoming Webhook URL for examples/webhook-slack.yaml, defaults to empty
#   TAG                Image tag to use, defaults to contents of VERSION file
#

GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
EXAMPLES_DIR="${GIT_ROOT}/examples"
VERSION_FILE="${GIT_ROOT}/VERSION"

CONCOURSE_TARGET="local"
CONCOURSE_URL="http://localhost:8080"
CONCOURSE_USER="local"
CONCOURSE_PASS="slacker"
CONCOURSE_READY_RETRIES=15
CONCOURSE_READY_WAIT=2

# Jobs that require manual setup outside the scope of this runner.
# Format: "pipeline/job-name"
SKIPPED_JOBS=(
	"thread-replies/thread-replies-with-thread-ts"
	# These jobs fetch the send-to-slack git resource from GitHub to read local fixture
	# files. They require outbound network access to github.com from the Concourse worker.
	"blocks-from-file/blocks-from-file-3"
	"blocks-from-file/concourse-metadata"
	# Video blocks require the youtube.com unfurl domain and links.embed:write scope
	# to be configured in the Slack app. These cannot be run without that setup.
	"video/basic-video"
	"video/video-with-description"
	"video/video-with-provider-info"
	"video/video-with-author-info"
	"video/video-with-all-fields"
	"video/video-with-other-blocks"
)

usage() {
	cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Starts Concourse, loads all example pipelines, and runs every job in order.

Options:
  --start-from <pipeline/job>  Skip all jobs before this one and start from here
  -h, --help                   Show this help message

Environment Variables:
  SLACK_BOT_USER_OAUTH_TOKEN  Required. Slack bot OAuth token.
  CHANNEL                     Required. Primary Slack channel name.
  SIDE_CHANNEL                Optional. Secondary Slack channel name.
  SLACK_WEBHOOK_URL           Optional. Webhook URL for webhook-slack example pipeline.
  TAG                         Optional. Image tag. Defaults to VERSION file contents.

EOF
}

# Check for required external commands
#
# Returns:
# - 0 if all dependencies are present
# - 1 if any dependency is missing
check_dependencies() {
	local missing_deps
	local required_commands
	local cmd

	missing_deps=()
	required_commands=("docker-compose" "fly" "yq")

	for cmd in "${required_commands[@]}"; do
		if ! command -v "${cmd}" >/dev/null 2>&1; then
			missing_deps+=("${cmd}")
		fi
	done

	if [[ ${#missing_deps[@]} -gt 0 ]]; then
		echo "check_dependencies:: missing required commands: ${missing_deps[*]}" >&2

		return 1
	fi

	return 0
}

# Validate required environment variables are set
#
# Returns:
# - 0 if all required variables are set
# - 1 if any required variable is missing
validate_env() {
	if [[ -z "${SLACK_BOT_USER_OAUTH_TOKEN:-}" ]]; then
		echo "validate_env:: SLACK_BOT_USER_OAUTH_TOKEN is required" >&2

		return 1
	fi

	if [[ -z "${CHANNEL:-}" ]]; then
		echo "validate_env:: CHANNEL is required" >&2

		return 1
	fi

	return 0
}

# Start Concourse and wait until the API is responsive
#
# Side Effects:
# - Starts docker-compose services defined in concourse/server.yaml
# - Polls the Concourse health endpoint until ready or retries are exhausted
#
# Returns:
# - 0 when Concourse is ready
# - 1 if Concourse does not become ready within the retry limit
start_concourse() {
	local i

	echo "start_concourse:: starting Concourse"
	if ! docker-compose -f "${GIT_ROOT}/concourse/server.yaml" up -d; then
		echo "start_concourse:: docker-compose failed to start" >&2

		return 1
	fi

	echo "start_concourse:: waiting for Concourse to become ready"
	i=0
	while ((i < CONCOURSE_READY_RETRIES)); do
		if curl -sf "${CONCOURSE_URL}/api/v1/info" >/dev/null 2>&1; then
			echo "start_concourse:: Concourse is ready"

			return 0
		fi
		sleep "${CONCOURSE_READY_WAIT}"
		((i++)) || true
	done

	echo "start_concourse:: Concourse did not become ready after ${CONCOURSE_READY_RETRIES} retries" >&2

	return 1
}

# Log in to the local Concourse target
#
# Side Effects:
# - Writes fly target credentials to ~/.flyrc
#
# Returns:
# - 0 on success
# - 1 on failure
login_concourse() {
	echo "login_concourse:: logging in to ${CONCOURSE_URL}"
	if ! fly -t "${CONCOURSE_TARGET}" login \
		-c "${CONCOURSE_URL}" \
		-u "${CONCOURSE_USER}" \
		-p "${CONCOURSE_PASS}"; then
		echo "login_concourse:: fly login failed" >&2

		return 1
	fi

	return 0
}

# Load all yaml pipelines from the examples directory into Concourse
#
# Inputs:
# - $1 tag, the image tag to pass as the TAG pipeline variable
#
# Side Effects:
# - Calls fly set-pipeline and fly unpause-pipeline for each yaml file
# - Passes SLACK_WEBHOOK_URL into fly set-pipeline for webhook example pipelines
#
# Returns:
# - 0 if all pipelines load successfully
# - 1 if any pipeline fails to load
load_pipelines() {
	local tag
	local file
	local pipeline

	tag="${1}"

	if [[ -z "${tag}" ]]; then
		echo "load_pipelines:: tag is required" >&2

		return 1
	fi

	for file in "${EXAMPLES_DIR}"/*.yaml; do
		pipeline="$(basename "${file}" .yaml)"
		echo "load_pipelines:: loading pipeline: ${pipeline}"

		if ! fly -t "${CONCOURSE_TARGET}" set-pipeline \
			-p "${pipeline}" \
			-c "${file}" \
			--non-interactive \
			-v SLACK_BOT_USER_OAUTH_TOKEN="${SLACK_BOT_USER_OAUTH_TOKEN}" \
			-v channel="${CHANNEL}" \
			-v side_channel="${SIDE_CHANNEL:-}" \
			-v SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}" \
			-v TAG="${tag}"; then
			echo "load_pipelines:: failed to load pipeline: ${pipeline}" >&2

			return 1
		fi

		if ! fly -t "${CONCOURSE_TARGET}" unpause-pipeline -p "${pipeline}"; then
			echo "load_pipelines:: failed to unpause pipeline: ${pipeline}" >&2

			return 1
		fi
	done

	return 0
}

# Trigger every job in every example pipeline and wait for each to finish
#
# Inputs:
# - $1 start_from, optional pipeline/job name to resume from, skipping all prior jobs
#
# Side Effects:
# - Calls fly trigger-job -w for each job in each pipeline, in yaml order
# - Skips any job listed in SKIPPED_JOBS
# - Skips webhook-slack notify job when SLACK_WEBHOOK_URL is unset
# - Exits as soon as any job fails
#
# Returns:
# - 0 if all jobs succeed
# - 1 if any job fails
run_all_jobs() {
	local start_from
	local skipping
	local file
	local pipeline
	local job_name
	local job_key
	local job_keys
	local total
	local current
	local skip
	local skipped
	local effective_skipped

	start_from="${1:-}"
	skipping="false"
	job_keys=()
	effective_skipped=("${SKIPPED_JOBS[@]}")
	if [[ -z "${SLACK_WEBHOOK_URL:-}" ]]; then
		effective_skipped+=("webhook-slack/notify-via-slack-webhook")
		echo "run_all_jobs:: SLACK_WEBHOOK_URL unset, skipping webhook-slack/notify-via-slack-webhook"
	fi

	if [[ -n "${start_from}" ]]; then
		skipping="true"
		echo "run_all_jobs:: will skip jobs until ${start_from}"
	fi

	for file in "${EXAMPLES_DIR}"/*.yaml; do
		pipeline="$(basename "${file}" .yaml)"

		while IFS= read -r job_name; do
			job_key="${pipeline}/${job_name}"

			if [[ "${skipping}" == "true" ]]; then
				if [[ "${job_key}" == "${start_from}" ]]; then
					skipping="false"
					echo "run_all_jobs:: resuming at ${job_key}"
				else
					echo "run_all_jobs:: skipping ${job_key}"
					continue
				fi
			fi

			skip="false"
			for skipped in "${effective_skipped[@]}"; do
				if [[ "${job_key}" == "${skipped}" ]]; then
					skip="true"
					break
				fi
			done

			if [[ "${skip}" == "true" ]]; then
				echo "run_all_jobs:: skipping ${job_key}, skip list match"
				continue
			fi

			job_keys+=("${job_key}")
		done < <(yq '.jobs[].name' "${file}")
	done

	if [[ "${skipping}" == "true" ]]; then
		echo "run_all_jobs:: --start-from '${start_from}' was never matched" >&2

		return 1
	fi

	total="${#job_keys[@]}"
	current=0

	for job_key in "${job_keys[@]}"; do
		((current++)) || true
		echo "run_all_jobs:: [${current}/${total}] triggering ${job_key}"

		if ! fly -t "${CONCOURSE_TARGET}" trigger-job \
			-j "${job_key}" \
			-w; then
			echo "run_all_jobs:: [${current}/${total}] job failed: ${job_key}" >&2

			return 1
		fi

		echo "run_all_jobs:: [${current}/${total}] completed ${job_key}"
	done

	return 0
}

# Send a header-only notification to the configured Slack channel
#
# Inputs:
# - $1 color, header color: success, warning, or danger
# - $2 text, header text to display
#
# Side Effects:
# - Pipes a JSON payload to send-to-slack.sh via stdin
# - Logs a warning to stderr if the send fails, does not abort the suite
#
# Returns:
# - 0 always
notify_slack() {
	local color
	local text
	local payload

	color="${1}"
	text="${2}"

	if [[ -z "${color}" ]]; then
		echo "notify_slack:: color is required" >&2

		return 1
	fi

	if [[ -z "${text}" ]]; then
		echo "notify_slack:: text is required" >&2

		return 1
	fi

	payload="$(jq -n \
		--arg token "${SLACK_BOT_USER_OAUTH_TOKEN}" \
		--arg channel "${CHANNEL}" \
		--arg color "${color}" \
		--arg text "${text}" \
		'{
			source: { slack_bot_user_oauth_token: $token },
			params: {
				channel: $channel,
				blocks: [{ header: { color: $color, text: { type: "plain_text", text: $text } } }]
			}
		}')"

	if ! echo "${payload}" | "${GIT_ROOT}/bin/send-to-slack.sh"; then
		echo "notify_slack:: warning: failed to send Slack notification" >&2
	fi

	return 0
}

main() {
	local tag
	local start_from

	start_from=""

	while [[ $# -gt 0 ]]; do
		case $1 in
		-h | --help) usage && return 0 ;;
		--start-from)
			if [[ $# -lt 2 ]]; then
				echo "--start-from requires a pipeline/job argument" >&2
				echo "Use '$(basename "$0") --help' for usage information" >&2

				return 1
			fi
			start_from="${2}"
			shift 2
			;;
		*)
			echo "Unknown option '${1}'" >&2
			echo "Use '$(basename "$0") --help' for usage information" >&2

			return 1
			;;
		esac
	done

	if ! check_dependencies; then
		return 1
	fi

	if ! validate_env; then
		return 1
	fi

	tag="${TAG:-$(cat "${VERSION_FILE}" 2>/dev/null || echo "latest")}"

	if ! start_concourse; then
		return 1
	fi

	if ! login_concourse; then
		return 1
	fi

	if ! load_pipelines "${tag}"; then
		return 1
	fi

	cat <<EOF
========================================
  EXAMPLE SUITE STARTING
  tag: ${tag}
EOF
	if [[ -n "${start_from}" ]]; then
		echo "  start-from: ${start_from}"
	fi
	cat <<EOF
========================================
EOF
	notify_slack "warning" "Example Suite Starting (tag: ${tag})"

	if ! run_all_jobs "${start_from}"; then
		cat <<EOF >&2
========================================
  EXAMPLE SUITE FAILED
========================================
EOF
		notify_slack "danger" "Example Suite Failed (tag: ${tag})"

		return 1
	fi

	cat <<EOF
========================================
  EXAMPLE SUITE PASSED
========================================
EOF
	notify_slack "success" "Example Suite Passed (tag: ${tag})"

	return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	set -eo pipefail
	umask 077
	main "$@"
	exit $?
fi
