#!/usr/bin/env bash
#
# Run make test inside a Docker container with the workspace mounted
set -euo pipefail

DOCKER_IMAGE_NAME="${DOCKER_IMAGE_NAME:-send-to-slack}"
DOCKER_IMAGE_TAG="${DOCKER_IMAGE_TAG:-docker-tests}"
DOCKERFILE_PATH="${DOCKERFILE_PATH:-tests/Dockerfile-test}"
DOCKER_PLATFORM="${DOCKER_PLATFORM:-linux/amd64}"
MAKE_COMMAND="${MAKE_COMMAND:-make test}"

# Print usage details for the script.
usage() {
	cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Build the test image and run make test inside a Docker container.

Environment overrides:
  DOCKER_IMAGE_NAME  Image name to build and run (default: send-to-slack)
  DOCKER_IMAGE_TAG   Image tag to build and run (default: docker-tests)
  DOCKERFILE_PATH    Dockerfile path (default: tests/Dockerfile-test)
  DOCKER_PLATFORM    Platform passed to docker build/run (default: linux/amd64)
  MAKE_COMMAND       Command executed inside the container (default: make test)

Options:
  -h, --help  Show this help message
EOF
}

# Resolve the repository root directory.
# Returns:
# - 0 on success
# - 1 when the path cannot be determined
resolve_workspace() {
	local script_dir
	script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	if [[ -z "$script_dir" ]]; then
		echo "resolve_workspace:: unable to determine script directory" >&2
		return 1
	fi

	echo "$script_dir"
	return 0
}

# Validate required inputs before running Docker operations.
# Returns:
# - 0 on success
# - 1 on validation error
validate_inputs() {
	local workspace
	workspace="$1"

	if [[ -z "$workspace" ]]; then
		echo "validate_inputs:: workspace path is empty" >&2
		return 1
	fi

	if [[ ! -f "${workspace}/${DOCKERFILE_PATH}" ]]; then
		echo "validate_inputs:: Dockerfile not found at ${workspace}/${DOCKERFILE_PATH}" >&2
		return 1
	fi

	if [[ -z "$DOCKER_IMAGE_NAME" ]] || [[ -z "$DOCKER_IMAGE_TAG" ]]; then
		echo "validate_inputs:: DOCKER_IMAGE_NAME and DOCKER_IMAGE_TAG are required" >&2
		return 1
	fi

	if [[ -z "$MAKE_COMMAND" ]]; then
		echo "validate_inputs:: MAKE_COMMAND is required" >&2
		return 1
	fi

	return 0
}

# Ensure Docker is installed and reachable.
# Returns:
# - 0 when Docker is available
# - 1 when Docker is missing
check_docker() {
	if ! command -v docker >/dev/null 2>&1; then
		echo "check_docker:: docker is required but not available" >&2
		return 1
	fi

	return 0
}

# Build the Docker image used for running tests.
# Returns:
# - 0 on success
# - 1 on failure
build_image() {
	local workspace
	workspace="$1"

	if ! docker build \
		--platform "${DOCKER_PLATFORM}" \
		-t "${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}" \
		-f "${workspace}/${DOCKERFILE_PATH}" \
		"${workspace}"; then
		echo "build_image:: failed to build Docker image" >&2
		return 1
	fi

	return 0
}

# Run make test inside the freshly built container with the workspace mounted.
# Returns:
# - 0 on success
# - 1 on failure
run_tests() {
	local workspace
	local docker_cmd
	workspace="$1"
	docker_cmd="cd /workspace && ${MAKE_COMMAND}"

	if ! docker run --rm -it \
		--platform "${DOCKER_PLATFORM}" \
		-v "${workspace}:/workspace" \
		-w /workspace \
		--entrypoint /bin/bash \
		"${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}" \
		-c "$docker_cmd"; then
		echo "run_tests:: failed to run make test in container" >&2
		return 1
	fi

	return 0
}

# Main entry point.
# Returns:
# - 0 on success
# - 1 on failure
main() {
	while [[ $# -gt 0 ]]; do
		case $1 in
		-h | --help)
			usage
			return 0
			;;
		*)
			echo "Unknown option '$1'" >&2
			echo "Use '$(basename "$0") --help' for usage information" >&2
			return 1
			;;
		esac
	done

	local workspace
	workspace="$(resolve_workspace)" || return 1

	if ! validate_inputs "$workspace"; then
		return 1
	fi

	if ! check_docker; then
		return 1
	fi

	if ! build_image "$workspace"; then
		return 1
	fi

	if ! run_tests "$workspace"; then
		return 1
	fi

	return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	main "$@"
	exit $?
fi
