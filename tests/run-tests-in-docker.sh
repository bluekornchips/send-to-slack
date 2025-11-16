#!/usr/bin/env bash
#
# Docker test script for send-to-slack
# Builds a local Docker image and runs tests inside the container
#
set -eo pipefail

DOCKER_IMAGE_NAME="${DOCKER_IMAGE_NAME:-send-to-slack}"
DOCKER_IMAGE_TAG="${DOCKER_IMAGE_TAG:-local}"
MAKE_COMMAND="${MAKE_COMMAND:-make test}"

# Get the project root directory
GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
if [[ -z "$GIT_ROOT" ]]; then
	echo "docker-test:: failed to get git root directory" >&2
	exit 1
fi

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
# Returns:
# - 0 on success
# - 1 on failure
run_tests() {
	local workspace_dir
	local docker_cmd

	if [[ -z "$DOCKER_IMAGE_NAME" ]] || [[ -z "$DOCKER_IMAGE_TAG" ]]; then
		echo "run_tests:: DOCKER_IMAGE_NAME and DOCKER_IMAGE_TAG are required" >&2
		return 1
	fi

	workspace_dir="${GIT_ROOT}"
	docker_cmd="cd /workspace && ${MAKE_COMMAND}"

	echo "Running tests in Docker container."
	if ! docker run --rm -it \
		--platform=linux/amd64 \
		-v "${workspace_dir}:/workspace" \
		-w /workspace \
		--user slack \
		--entrypoint /bin/bash \
		"${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}" \
		-c "$docker_cmd"; then
		echo "run_tests:: failed to run tests in container" >&2
		return 1
	fi

	return 0
}

# Main entry point
#
# Returns:
# - 0 on success
# - 1 on failure
main() {
	if ! check_docker; then
		return 1
	fi

	if ! build_image; then
		return 1
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
