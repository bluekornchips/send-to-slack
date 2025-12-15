#!/usr/bin/env bash
#
# Docker test script for send-to-slack
# Mounts the repo in a container and runs tests
#
set -eo pipefail

DOCKER_IMAGE="${DOCKER_IMAGE:-}"
DOCKER_IMAGE_NAME="${DOCKER_IMAGE_NAME:-send-to-slack}"
DOCKER_IMAGE_TAG="${DOCKER_IMAGE_TAG:-local}"
MAKE_COMMAND="${MAKE_COMMAND:-make test}"

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

print_start_info() {
	local token_status
	local channel_status
	local image_info

	token_status="missing"
	[[ -n "$SLACK_BOT_USER_OAUTH_TOKEN" ]] && token_status="present"

	channel_status="<unset>"
	[[ -n "$CHANNEL" ]] && channel_status="$CHANNEL"

	if [[ -n "$DOCKER_IMAGE" ]]; then
		image_info="Using existing image: ${DOCKER_IMAGE}"
	else
		image_info="Building image: ${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG} (from tests/Dockerfile-test)"
	fi

	cat <<EOF
Starting dockerized tests for send-to-slack
Project root: ${GIT_ROOT}
${image_info}
Make command: ${MAKE_COMMAND}
Platform: linux/amd64
Channel: ${channel_status}
Slack OAuth token: ${token_status}
EOF
}

require_env() {
	local missing=0
	local sudo_hint=""
	if [[ -n "${SUDO_USER:-}" ]]; then
		sudo_hint="When using sudo, run with sudo -E or prefix the command, e.g. 'sudo CHANNEL=... SLACK_BOT_USER_OAUTH_TOKEN=... make test-in-docker'."
	fi

	if [[ -z "${CHANNEL:-}" ]]; then
		echo "Missing required environment value: CHANNEL" >&2
		[[ -n "$sudo_hint" ]] && echo "$sudo_hint" >&2
		missing=1
	fi
	if [[ -z "${SLACK_BOT_USER_OAUTH_TOKEN:-}" ]]; then
		echo "Missing required environment value: SLACK_BOT_USER_OAUTH_TOKEN" >&2
		[[ -n "$sudo_hint" ]] && echo "$sudo_hint" >&2
		missing=1
	fi

	# ensure they are exported so docker inherits them
	if [[ $missing -eq 0 ]]; then
		export CHANNEL
		export SLACK_BOT_USER_OAUTH_TOKEN
	fi

	return $missing
}

# Check if Docker is available
#
# Returns:
# - 0 if Docker is available
# - 1 if Docker is not available
check_docker() {
	if ! command -v docker >/dev/null 2>&1; then
		echo "check_docker:: docker is required but not installed" >&2
		return 1
	fi

	return 0
}

# Build the Docker image using Dockerfile-test
#
# Returns:
# - 0 on success
# - 1 on failure
build_image() {
	if [[ -z "$DOCKER_IMAGE_NAME" ]] || [[ -z "$DOCKER_IMAGE_TAG" ]]; then
		echo "build_image:: DOCKER_IMAGE_NAME and DOCKER_IMAGE_TAG are required" >&2
		return 1
	fi

	echo "Building Docker image ${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG} from tests/Dockerfile-test."
	cd "${GIT_ROOT}" || return 1
	if ! docker build -t "${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}" -f tests/Dockerfile-test .; then
		echo "build_image:: failed to build Docker image" >&2
		return 1
	fi

	return 0
}

# Run tests in the Docker container
#
# Creates an isolated copy of the workspace to prevent git operations
# inside the container from affecting the actual repository.
#
# Returns:
# - 0 on success
# - 1 on failure
run_tests() {
	local workspace_dir
	local temp_workspace
	local docker_cmd
	local docker_flags
	local image_ref

	if [[ -n "$DOCKER_IMAGE" ]]; then
		image_ref="$DOCKER_IMAGE"
	else
		if [[ -z "$DOCKER_IMAGE_NAME" ]] || [[ -z "$DOCKER_IMAGE_TAG" ]]; then
			echo "run_tests:: DOCKER_IMAGE_NAME and DOCKER_IMAGE_TAG are required when not using DOCKER_IMAGE" >&2
			return 1
		fi
		image_ref="${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}"
	fi

	# Create isolated workspace copy to prevent container git ops from affecting host repo
	temp_workspace="$(mktemp -d)"
	trap 'rm -rf "$temp_workspace"' EXIT

	echo "Creating isolated workspace copy at ${temp_workspace}"
	# Copy workspace excluding .git directory to isolate from host repository
	rsync -a --exclude='.git' "${GIT_ROOT}/" "${temp_workspace}/"

	workspace_dir="${temp_workspace}"
	docker_cmd="$(
		cat <<EOF
cd /workspace && git init -q && git config user.email 'test@test.com' && git config user.name 'Test' && git add -A && git commit -q -m 'test' && ${MAKE_COMMAND}
EOF
	)"

	echo "docker_cmd: $docker_cmd"
	docker_flags=(
		--rm
		-i
		--platform=linux/amd64
		-e CHANNEL
		-e SLACK_BOT_USER_OAUTH_TOKEN
		-v "${workspace_dir}:/workspace"
		-w /workspace
		--entrypoint /bin/bash
	)

	if [[ -t 1 ]]; then
		docker_flags+=(-t)
	fi

	echo "Running tests in Docker container using image: ${image_ref}"
	if ! docker run "${docker_flags[@]}" "$image_ref" -c "$docker_cmd"; then
		echo "run_tests:: failed to run tests in container" >&2
		return 1
	fi

	return 0
}

# Parse command line arguments
#
# Inputs:
# - $@ - command line arguments
#
# Returns:
# - 0 on success
# - 1 on failure
parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-i | --image)
			if [[ -z "${2:-}" ]]; then
				echo "parse_args:: option $1 requires an argument" >&2
				return 1
			fi
			DOCKER_IMAGE="$2"
			shift 2
			;;
		-m | --make)
			if [[ -z "${2:-}" ]]; then
				echo "parse_args:: option $1 requires an argument" >&2
				return 1
			fi
			MAKE_COMMAND="$2"
			shift 2
			;;
		-h | --help)
			cat <<EOF >&2
usage: $0 [OPTIONS]

Run tests in a Docker container by mounting the repo.

OPTIONS:
  -i, --image IMAGE    Docker image to use (optional)
                       Can be a repo:tag (e.g., "myrepo:tag") or image ID (e.g., "c56903e46f90")
                       If not provided, builds from tests/Dockerfile-test
  -m, --make COMMAND   Make command to run (default: make test)
  -h, --help           Show this help message

ENVIRONMENT VARIABLES:
  DOCKER_IMAGE         Docker image to use (same as -i/--image, optional)
  DOCKER_IMAGE_NAME    Image name when building (default: send-to-slack)
  DOCKER_IMAGE_TAG     Image tag when building (default: local)
  MAKE_COMMAND         Command to run in container (default: make test)
  CHANNEL              Required: Slack channel for tests
  SLACK_BOT_USER_OAUTH_TOKEN  Required: Slack OAuth token for tests

EXAMPLES:
  # Build and use default image (send-to-slack:local)
  $0

  # Use image by ID
  $0 --image c56903e46f90

  # Use image by repo:tag
  $0 --image myrepo/send-to-slack:v1.0.0

  # Use image and custom make command
  $0 --image c56903e46f90 --make "make test-smoke test-acceptance"

  # Use environment variable
  DOCKER_IMAGE=c56903e46f90 $0
EOF
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

	print_start_info

	if ! check_docker; then
		return 1
	fi

	if ! require_env CHANNEL SLACK_BOT_USER_OAUTH_TOKEN; then
		return 1
	fi

	if [[ -z "$DOCKER_IMAGE" ]]; then
		if ! build_image; then
			return 1
		fi
	fi

	if ! run_tests; then
		return 1
	fi

	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
	exit $?
fi
