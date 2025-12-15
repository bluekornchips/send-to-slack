#!/usr/bin/env bash
#
# Build script for send-to-slack Docker image
# Builds the Dockerfile and optionally handles GitHub Actions environment variables
#
set -eo pipefail

DOCKER_IMAGE_NAME="${DOCKER_IMAGE_NAME:-send-to-slack}"
DOCKER_IMAGE_TAG="${DOCKER_IMAGE_TAG:-local}"
GITHUB_ACTION="${GITHUB_ACTION:-false}"

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

Build the send-to-slack Docker image from Dockerfile.

OPTIONS:
  --gha, --github-action    Enable GitHub Actions mode (reads GHA environment variables)
  -h, --help                Show this help message

ENVIRONMENT VARIABLES:
  DOCKER_IMAGE_NAME         Image name (default: send-to-slack)
  DOCKER_IMAGE_TAG          Image tag (default: local)
  
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

  # GitHub Actions build
  $0 --gha
EOF
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

	echo "Building Docker image ${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG} from Dockerfile."
	cd "${GIT_ROOT}" || return 1
	if ! docker build \
		--platform linux/amd64 \
		-t "${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}" \
		-f Dockerfile .; then
		echo "build_image:: failed to build Docker image" >&2
		return 1
	fi

	echo "Successfully built ${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}"
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

	if [[ "$GITHUB_ACTION" == "true" ]]; then
		if ! extract_github_metadata; then
			return 1
		fi
	fi

	if ! build_image; then
		return 1
	fi

	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
	exit $?
fi
