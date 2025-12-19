#!/usr/bin/env bash
#
# Build script for send-to-slack Docker image
# Builds the Dockerfile and optionally runs healthcheck/test message
#
# Only enable strict error handling when executed directly, not when sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	set -eo pipefail
fi

DOCKER_IMAGE_NAME="${DOCKER_IMAGE_NAME:-send-to-slack}"
DOCKER_IMAGE_TAG="${DOCKER_IMAGE_TAG:-local}"
GITHUB_ACTION="${GITHUB_ACTION:-false}"
NO_CACHE="${NO_CACHE:-true}"
SEND_HEALTHCHECK_QUERY="${SEND_HEALTHCHECK_QUERY:-false}"
SEND_TEST_MESSAGE="${SEND_TEST_MESSAGE:-false}"
DOCKERFILE_CHOICE="${DOCKERFILE_CHOICE:-}"

# Get the project root directory
GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
if [[ -z "$GIT_ROOT" ]]; then
	script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
	GIT_ROOT="$script_dir"
fi

if [[ -z "$GIT_ROOT" ]]; then
	echo "Failed to determine project root directory" >&2
	exit 1
fi

# Display usage information
#
# Returns:
# - 0 always
usage() {
	cat <<EOF
usage: $0 [OPTIONS]

Build the send-to-slack Docker image from Docker/Dockerfile.

OPTIONS:
  --gha, --github-action    Enable GitHub Actions mode (reads GHA environment variables)
  --no-cache                Disable Docker build cache (default: disabled)
  --healthcheck             Run ./bin/send-to-slack.sh --health-check after build
  --send-test-message       Send a test message after build (requires CHANNEL and SLACK_BOT_USER_OAUTH_TOKEN)
  --dockerfile <name>       Which Dockerfile to build: concourse | test | remote | all (default: Docker/Dockerfile)
                            Use "all" to build all Dockerfiles one by one
  -h, --help                Show this help message

ENVIRONMENT VARIABLES:
  DOCKER_IMAGE_NAME         	Image name (default: send-to-slack)
  DOCKER_IMAGE_TAG          	Image tag (default: local)
  NO_CACHE                  	Disable Docker build cache (default: true)
  CHANNEL                   	Required for --send-test-message
  SLACK_BOT_USER_OAUTH_TOKEN  Required for --send-test-message
  
  GitHub Actions variables (only used with --gha flag):
    GITHUB_EVENT_NAME       Event type (pull_request, push, etc.)
    GITHUB_HEAD_REF         Branch name for pull requests
    GITHUB_REF_NAME         Branch name for pushes
    GITHUB_EVENT_PULL_REQUEST_NUMBER  PR number
    GITHUB_EVENT_PULL_REQUEST_HTML_URL  PR URL
    GITHUB_SHA              Commit SHA
    GITHUB_REPOSITORY       Repository name
    GITHUB_SERVER_URL       GitHub server URL
    GITHUB_RUN_ID           Workflow run ID

EXAMPLES:
  # Local build
  $0

  # Build with custom name and tag
  DOCKER_IMAGE_NAME=myimage DOCKER_IMAGE_TAG=v1.0.0 $0

  # Build with healthcheck and test message
  CHANNEL=#test SLACK_BOT_USER_OAUTH_TOKEN=token $0 --healthcheck --send-test-message

  # GitHub Actions build
  $0 --gha

  # Build without cache (default behavior)
  $0

  # Build with cache enabled
  NO_CACHE=false $0
EOF
	return 0
}

# Check for required external commands
# Returns 0 on success, 1 on missing commands
check_dependencies() {
	local missing_deps=()
	local required_commands=("jq" "envsubst" "docker" "git")

	for cmd in "${required_commands[@]}"; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			missing_deps+=("$cmd")
		fi
	done

	if [[ ${#missing_deps[@]} -gt 0 ]]; then
		echo "check_dependencies:: missing required dependencies: ${missing_deps[*]}" >&2
		echo "check_dependencies:: please install missing dependencies and try again" >&2
		return 1
	fi

	return 0
}

# Parse command line arguments
#
# Returns:
# - 0 on success
# - 1 on failure
# - 2 if help was requested
parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--gha | --github-action)
			GITHUB_ACTION="true"
			export GITHUB_ACTION
			shift
			;;
		--no-cache)
			NO_CACHE="true"
			export NO_CACHE
			shift
			;;
		--healthcheck)
			SEND_HEALTHCHECK_QUERY="true"
			export SEND_HEALTHCHECK_QUERY
			shift
			;;
		--send-test-message)
			SEND_TEST_MESSAGE="true"
			export SEND_TEST_MESSAGE
			shift
			;;
		--dockerfile)
			shift
			if [[ $# -eq 0 ]]; then
				echo "parse_args:: option --dockerfile requires an argument" >&2
				return 1
			fi
			if [[ -n "$1" ]]; then
				# Non-empty value must match valid choices
				case "$1" in
				concourse | test | remote | all)
					DOCKERFILE_CHOICE="$1"
					export DOCKERFILE_CHOICE
					;;
				*)
					echo "parse_args:: invalid dockerfile choice: $1 (allowed: concourse|test|remote|all)" >&2
					return 1
					;;
				esac
			else
				DOCKERFILE_CHOICE=""
				export DOCKERFILE_CHOICE
			fi
			shift
			;;
		-h | --help)
			usage
			return 2
			;;
		*)
			echo "parse_args:: unknown option: $1" >&2
			return 1
			;;
		esac
	done

	return 0
}

# Extract GitHub Actions metadata
#
# Sets environment variables for use in notification blocks
#
# Returns:
# - 0 on success
# - 1 on failure
extract_github_metadata() {
	if [[ "$GITHUB_ACTION" != "true" ]]; then
		return 0
	fi

	local event_name="${GITHUB_EVENT_NAME:-}"
	local branch_name
	local pr_number="${GITHUB_EVENT_PULL_REQUEST_NUMBER:-}"
	local pr_url="${GITHUB_EVENT_PULL_REQUEST_HTML_URL:-}"
	local commit_sha="${GITHUB_SHA:-}"
	local repo="${GITHUB_REPOSITORY:-}"
	local server_url="${GITHUB_SERVER_URL:-https://github.com}"
	local run_id="${GITHUB_RUN_ID:-}"

	if [[ -z "$event_name" ]]; then
		echo "extract_github_metadata:: GITHUB_EVENT_NAME is required in GitHub Actions mode" >&2
		return 1
	fi

	if [[ "$event_name" == "pull_request" ]]; then
		branch_name="${GITHUB_HEAD_REF:-}"
		if [[ -z "$branch_name" ]]; then
			echo "extract_github_metadata:: GITHUB_HEAD_REF is required for pull_request events" >&2
			return 1
		fi
	else
		branch_name="${GITHUB_REF_NAME:-}"
		if [[ -z "$branch_name" ]]; then
			echo "extract_github_metadata:: GITHUB_REF_NAME is required for non-pull_request events" >&2
			return 1
		fi
	fi

	if [[ -z "$commit_sha" ]]; then
		echo "extract_github_metadata:: GITHUB_SHA is required" >&2
		return 1
	fi

	local commit_short="${commit_sha:0:7}"
	local timestamp
	timestamp=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
	local workflow_run_url="${server_url}/${repo}/actions/runs/${run_id}"

	# Export variables for use in notification template
	export EVENT_TYPE
	if [[ "$event_name" == "pull_request" ]]; then
		EVENT_TYPE="Pull Request"
	else
		EVENT_TYPE="Push"
	fi

	export BRANCH="$branch_name"
	export COMMIT_SHA="$commit_sha"
	export COMMIT_SHORT="$commit_short"
	export PR_NUMBER="$pr_number"
	export PR_URL="$pr_url"
	export TIMESTAMP="$timestamp"
	export WORKFLOW_RUN_URL="$workflow_run_url"
	export REPO="$repo"

	return 0
}

# Build the Docker image
#
# Returns:
# - 0 on success
# - 1 on failure
build_image() {
	if [[ -z "$DOCKER_IMAGE_NAME" ]] || [[ -z "$DOCKER_IMAGE_TAG" ]]; then
		echo "build_image:: DOCKER_IMAGE_NAME and DOCKER_IMAGE_TAG are required" >&2
		return 1
	fi

	# Get repo and branch from env vars, git, or defaults
	local build_repo="${GITHUB_REPOSITORY:-}"
	local build_branch="${GITHUB_HEAD_REF:-${GITHUB_REF_NAME:-}}"

	if [[ -z "$build_repo" ]] && command -v git >/dev/null 2>&1; then
		local git_url
		git_url=$(git config --get remote.origin.url 2>/dev/null || echo '')
		if [[ "$git_url" =~ github\.com[:/]([^/]+/[^/]+) ]]; then
			build_repo="${BASH_REMATCH[1]}"
		fi
	fi

	if [[ -z "$build_branch" ]] && command -v git >/dev/null 2>&1; then
		build_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')
	fi

	build_repo="${build_repo:-bluekornchips/send-to-slack}"
	build_branch="${build_branch:-main}"

	local dockerfile_path
	case "$DOCKERFILE_CHOICE" in
	concourse)
		dockerfile_path="Docker/Dockerfile.concourse"
		;;
	test)
		dockerfile_path="Docker/Dockerfile.test"
		;;
	remote)
		dockerfile_path="Docker/Dockerfile.remote"
		;;
	*)
		dockerfile_path="Docker/Dockerfile"
		;;
	esac

	echo "Building Docker image ${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG} from ${dockerfile_path}."
	cd "${GIT_ROOT}" || return 1

	local docker_build_args=(
		--platform linux/amd64
		-t "${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}"
		-f "$dockerfile_path"
		--build-arg "GITHUB_REPOSITORY=${build_repo}"
		--build-arg "GITHUB_REF_NAME=${build_branch}"
	)

	if [[ "$NO_CACHE" == "true" ]]; then
		docker_build_args+=(--no-cache)
	fi

	if ! docker build "${docker_build_args[@]}" .; then
		echo "build_image:: failed to build Docker image using ${dockerfile_path}" >&2
		return 1
	fi

	echo "Successfully built ${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}"
	return 0
}

# Build all Dockerfiles sequentially
#
# Returns:
# - 0 on success
# - 1 on failure
build_all_images() {
	local dockerfiles=("" "concourse" "test" "remote")
	local dockerfile_names=("Dockerfile" "Dockerfile.concourse" "Dockerfile.test" "Dockerfile.remote")
	local original_choice="$DOCKERFILE_CHOICE"
	local build_count=0
	local failed_count=0

	echo "build_all_images:: building all Dockerfiles"
	for i in "${!dockerfiles[@]}"; do
		local choice="${dockerfiles[$i]}"
		local name="${dockerfile_names[$i]}"
		local current_num
		DOCKERFILE_CHOICE="$choice"
		current_num=$((i + 1))

		echo "build_all_images:: building ${name} (${current_num}/${#dockerfiles[@]})"
		if ! build_image; then
			echo "build_all_images:: failed to build ${name}" >&2
			((failed_count++))
		else
			((build_count++))
		fi
	done

	DOCKERFILE_CHOICE="$original_choice"

	if [[ $failed_count -gt 0 ]]; then
		echo "build_all_images:: completed with ${failed_count} failure(s), ${build_count} success(es)" >&2
		return 1
	fi

	echo "build_all_images:: successfully built all ${build_count} Dockerfile(s)"
	return 0
}

# Run healthcheck using local script
run_healthcheck() {
	local script_path="${GIT_ROOT}/bin/send-to-slack.sh"

	if [[ ! -x "$script_path" ]]; then
		echo "run_healthcheck:: script not executable: $script_path" >&2
		return 1
	fi

	if ! "$script_path" --health-check; then
		echo "run_healthcheck:: health-check failed" >&2
		return 1
	fi

	echo "run_healthcheck:: health-check passed"
	return 0
}

# Send a test message using local script
send_test_message() {
	local script_path="${GIT_ROOT}/bin/send-to-slack.sh"
	local payload_file

	if [[ -z "${CHANNEL:-}" ]]; then
		echo "send_test_message:: CHANNEL is required" >&2
		return 1
	fi

	if [[ -z "${SLACK_BOT_USER_OAUTH_TOKEN:-}" ]]; then
		echo "send_test_message:: SLACK_BOT_USER_OAUTH_TOKEN is required" >&2
		return 1
	fi

	if [[ ! -x "$script_path" ]]; then
		echo "send_test_message:: script not executable: $script_path" >&2
		return 1
	fi

	local dockerfile_display
	if [[ -z "$DOCKERFILE_CHOICE" ]]; then
		dockerfile_display="Dockerfile"
	elif [[ "$DOCKERFILE_CHOICE" == "all" ]]; then
		dockerfile_display="all"
	else
		dockerfile_display="Dockerfile.${DOCKERFILE_CHOICE}"
	fi

	payload_file=$(mktemp)

	# Always use table format
	# Try to get branch and commit from git if not available from CI metadata
	local branch_value="${BRANCH:-}"
	local commit_short_value="${COMMIT_SHORT:-}"
	local commit_sha_value="${COMMIT_SHA:-}"
	local repo_value="${REPO:-}"

	if [[ -z "$branch_value" ]] && command -v git >/dev/null 2>&1; then
		branch_value=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
	fi

	if [[ -z "$commit_short_value" ]] && command -v git >/dev/null 2>&1; then
		commit_sha_value=$(git rev-parse HEAD 2>/dev/null || echo "")
		if [[ -n "$commit_sha_value" ]]; then
			commit_short_value="${commit_sha_value:0:7}"
		fi
	fi

	if [[ -z "$repo_value" ]] && command -v git >/dev/null 2>&1; then
		local git_url
		git_url=$(git config --get remote.origin.url 2>/dev/null || echo '')
		if [[ "$git_url" =~ github\.com[:/]([^/]+/[^/]+) ]]; then
			repo_value="${BASH_REMATCH[1]}"
		fi
	fi

	# Build horizontal table: Repository | Branch | Commit | Event | Workflow Run | Message
	local rows_array='[]'

	# Get server URL for constructing links
	local server_url="${GITHUB_SERVER_URL:-https://github.com}"

	# Prepare cell values
	local repo_cell
	if [[ -n "$repo_value" ]]; then
		local repo_url="${server_url}/${repo_value}"
		repo_cell=$(jq -n --arg rp "$repo_value" --arg ru "$repo_url" '{"type": "rich_text", "elements": [{"type": "rich_text_section", "elements": [{"type": "link", "url": $ru, "text": $rp}]}]}')
	else
		repo_cell='{"type": "raw_text", "text": "N/A"}'
	fi

	local branch_cell
	if [[ -n "$branch_value" ]] && [[ -n "$repo_value" ]]; then
		local branch_url="${server_url}/${repo_value}/tree/${branch_value}"
		branch_cell=$(jq -n --arg br "$branch_value" --arg bu "$branch_url" '{"type": "rich_text", "elements": [{"type": "rich_text_section", "elements": [{"type": "link", "url": $bu, "text": $br}]}]}')
	else
		if [[ -n "$branch_value" ]]; then
			branch_cell=$(jq -n --arg br "$branch_value" '{"type": "raw_text", "text": $br}')
		else
			branch_cell='{"type": "raw_text", "text": "N/A"}'
		fi
	fi

	local commit_cell
	if [[ -n "$commit_short_value" ]]; then
		if [[ -n "$commit_sha_value" ]] && [[ -n "$repo_value" ]]; then
			local commit_url="${server_url}/${repo_value}/commit/${commit_sha_value}"
			commit_cell=$(jq -n --arg cs "$commit_short_value" --arg cu "$commit_url" '{"type": "rich_text", "elements": [{"type": "rich_text_section", "elements": [{"type": "link", "url": $cu, "text": $cs}]}]}')
		else
			commit_cell=$(jq -n --arg cs "$commit_short_value" '{"type": "raw_text", "text": $cs}')
		fi
	else
		commit_cell='{"type": "raw_text", "text": "N/A"}'
	fi

	local event_cell
	if [[ -n "${EVENT_TYPE:-}" ]]; then
		event_cell=$(jq -n --arg et "${EVENT_TYPE}" '{"type": "raw_text", "text": $et}')
	else
		event_cell='{"type": "raw_text", "text": "N/A"}'
	fi

	local workflow_cell
	if [[ -n "${WORKFLOW_RUN_URL:-}" ]]; then
		workflow_cell=$(jq -n --arg wu "${WORKFLOW_RUN_URL}" '{"type": "rich_text", "elements": [{"type": "rich_text_section", "elements": [{"type": "link", "url": $wu, "text": "View Run"}]}]}')
	else
		workflow_cell='{"type": "raw_text", "text": "N/A"}'
	fi

	local message_cell
	message_cell=$(jq -n --arg df "$dockerfile_display" '{"type": "raw_text", "text": "Dockerfile: \($df) - Send test message to slack success"}')

	rows_array=$(jq -n '[[
		{"type": "raw_text", "text": "Repository"},
		{"type": "raw_text", "text": "Branch"},
		{"type": "raw_text", "text": "Commit"},
		{"type": "raw_text", "text": "Event"},
		{"type": "raw_text", "text": "Workflow Run"},
		{"type": "raw_text", "text": "Message"}
	]]')

	# Data row
	local data_row
	data_row=$(jq -n \
		--argjson repo "$repo_cell" \
		--argjson branch "$branch_cell" \
		--argjson commit "$commit_cell" \
		--argjson event "$event_cell" \
		--argjson workflow "$workflow_cell" \
		--argjson message "$message_cell" \
		'[$repo, $branch, $commit, $event, $workflow, $message]')

	rows_array=$(echo "$rows_array" | jq --argjson data_row "$data_row" '. + [$data_row]')

	# Build final payload
	jq -n \
		--arg token "${SLACK_BOT_USER_OAUTH_TOKEN}" \
		--arg channel "${CHANNEL}" \
		--argjson rows "$rows_array" \
		'{
			"source": {
				"slack_bot_user_oauth_token": $token
			},
			"params": {
				"channel": $channel,
				"blocks": [
					{
						"type": "table",
						"rows": $rows
					}
				]
			}
		}' >"$payload_file"

	if ! "$script_path" --file "$payload_file"; then
		rm -f "$payload_file"
		echo "send_test_message:: failed to send test message" >&2
		return 1
	fi

	rm -f "$payload_file"
	echo "send_test_message:: test message sent"
	return 0
}

# Main entry point
#
# Returns:
# - 0 on success
# - 1 on failure
main() {
	local parse_result

	parse_result=0
	parse_args "$@" || parse_result=$?

	if [[ $parse_result -eq 2 ]]; then
		return 0
	fi

	if [[ $parse_result -ne 0 ]]; then
		return 1
	fi

	if ! check_dependencies; then
		return 1
	fi

	if [[ "$GITHUB_ACTION" == "true" ]]; then
		if ! extract_github_metadata; then
			return 1
		fi
	fi

	local dockerfiles
	local dockerfile_names
	local original_choice="$DOCKERFILE_CHOICE"

	if [[ "$DOCKERFILE_CHOICE" == "all" ]]; then
		if ! build_all_images; then
			return 1
		fi
		dockerfiles=("" "concourse" "test" "remote")
		dockerfile_names=("Dockerfile" "Dockerfile.concourse" "Dockerfile.test" "Dockerfile.remote")
	else
		if ! build_image; then
			return 1
		fi
		dockerfiles=("$DOCKERFILE_CHOICE")
		if [[ -z "$DOCKERFILE_CHOICE" ]]; then
			dockerfile_names=("Dockerfile")
		else
			dockerfile_names=("Dockerfile.${DOCKERFILE_CHOICE}")
		fi
	fi

	for i in "${!dockerfiles[@]}"; do
		local choice="${dockerfiles[$i]}"
		local name="${dockerfile_names[$i]}"
		DOCKERFILE_CHOICE="$choice"

		if [[ "$SEND_HEALTHCHECK_QUERY" == "true" ]]; then
			if [[ "$original_choice" == "all" ]]; then
				echo "Running healthcheck for ${name}"
			fi
			if ! run_healthcheck; then
				DOCKERFILE_CHOICE="$original_choice"
				return 1
			fi
		fi

		if [[ "$SEND_TEST_MESSAGE" == "true" ]]; then
			if [[ "$original_choice" == "all" ]]; then
				echo "Sending test message for ${name}"
			fi
			if ! send_test_message; then
				DOCKERFILE_CHOICE="$original_choice"
				return 1
			fi
		fi
	done

	DOCKERFILE_CHOICE="$original_choice"

	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
	exit $?
fi
