#!/usr/bin/env bash
#
# Build test script for send-to-slack
# Builds the Docker image and sends a test notification
#
set -eo pipefail

DOCKER_IMAGE_TAG="${DOCKER_IMAGE_TAG:-local}"
DOCKER_IMAGE_ID="${DOCKER_IMAGE_ID:-}"
CHANNEL="${CHANNEL:-}"
SLACK_BOT_USER_OAUTH_TOKEN="${SLACK_BOT_USER_OAUTH_TOKEN:-}"

# Get the project root directory based on script location
GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
# Verify git root is the correct project, otherwise use script location
if [[ -z "$GIT_ROOT" ]] || [[ ! -f "${GIT_ROOT}/bin/send-to-slack.sh" ]]; then
	GIT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fi

# Verify it's the correct directory by checking for expected files
if [[ ! -f "${GIT_ROOT}/bin/send-to-slack.sh" ]]; then
	echo "Failed to determine project root directory. Expected files not found in: $GIT_ROOT" >&2
	exit 1
fi

# Display usage information
#
# Returns:
# - 0 always
usage() {
	cat <<EOF
usage: $0 [OPTIONS]

Build the Docker image and send a test notification to Slack.

OPTIONS:
  -t, --tag TAG            Docker image tag or full image:tag reference (default: local)
                           - Tag: v1.0.0 (uses DOCKER_IMAGE_NAME)
                           - Full reference: registry/repo:tag
  -i, --image IMAGE_ID     Docker image ID to use for testing (overrides -t/--tag)
  -h, --help               Show this help message

ENVIRONMENT VARIABLES:
  CHANNEL                  Required: Slack channel to send notification to
  SLACK_BOT_USER_OAUTH_TOKEN  Required: Slack OAuth token
  DOCKER_IMAGE_NAME        Image name (default: send-to-slack)
  DOCKER_IMAGE_TAG         Image tag (default: local, overridden by -t/--tag)
  DOCKER_IMAGE_ID          Image ID (overridden by -i/--image)

EXAMPLES:
  # Build and test with default tag
  CHANNEL=#test SLACK_BOT_USER_OAUTH_TOKEN=token $0

  # Build and test with custom tag
  CHANNEL=#test SLACK_BOT_USER_OAUTH_TOKEN=token $0 --tag v1.0.0

  # Test using an existing image by ID
  CHANNEL=#test SLACK_BOT_USER_OAUTH_TOKEN=token $0 --image efa4fc963b0e

  # Test using a full image reference
  CHANNEL=#test SLACK_BOT_USER_OAUTH_TOKEN=token $0 --tag registry/repo:tag
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
		-t | --tag)
			if [[ -z "${2:-}" ]]; then
				echo "parse_args:: option $1 requires an argument" >&2
				return 1
			fi
			# If tag contains ':', treat it as full image:tag reference
			if [[ "$2" == *:* ]]; then
				DOCKER_IMAGE_NAME="${2%%:*}"
				DOCKER_IMAGE_TAG="${2#*:}"
			else
				DOCKER_IMAGE_TAG="$2"
			fi
			shift 2
			;;
		-i | --image)
			if [[ -z "${2:-}" ]]; then
				echo "parse_args:: option $1 requires an argument" >&2
				return 1
			fi
			DOCKER_IMAGE_ID="$2"
			shift 2
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

# Check required environment variables
#
# Returns:
# - 0 if all required vars are set
# - 1 if any are missing
check_env() {
	local missing=0

	if [[ -z "${CHANNEL:-}" ]]; then
		echo "check_env:: CHANNEL environment variable is required" >&2
		missing=1
	fi

	if [[ -z "${SLACK_BOT_USER_OAUTH_TOKEN:-}" ]]; then
		echo "check_env:: SLACK_BOT_USER_OAUTH_TOKEN environment variable is required" >&2
		missing=1
	fi

	return $missing
}

# Check for required external commands
#
# Returns:
#   0 if all dependencies are available
#   1 if any dependency is missing
check_dependencies() {
	local missing_deps=()
	local required_commands=("jq" "curl" "envsubst" "rsync" "docker" "git")

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

# Build the image using build.sh
#
# Returns:
# - 0 on success
# - 1 on failure
build_image() {
	local build_script="${GIT_ROOT}/ci/build.sh"

	if [[ ! -f "$build_script" ]]; then
		echo "build_image:: build.sh not found: $build_script" >&2
		return 1
	fi

	if [[ ! -x "$build_script" ]]; then
		chmod +x "$build_script"
	fi

	echo "Running build.sh to create Docker image".
	if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
		if ! "$build_script" --gha; then
			echo "build_image:: failed to build image" >&2
			return 1
		fi
	else
		if ! "$build_script"; then
			echo "build_image:: failed to build image" >&2
			return 1
		fi
	fi

	return 0
}

# Send notification using the built image
#
# Returns:
# - 0 on success
# - 1 on failure
send_notification() {
	local docker_image_name="${DOCKER_IMAGE_NAME:-send-to-slack}"
	local image_ref

	# If image ID is specified, use it directly
	if [[ -n "${DOCKER_IMAGE_ID:-}" ]]; then
		image_ref="$DOCKER_IMAGE_ID"
	# If DOCKER_IMAGE_TAG contains ':', it's already a full image:tag reference
	elif [[ "$DOCKER_IMAGE_TAG" == *:* ]]; then
		image_ref="$DOCKER_IMAGE_TAG"
	else
		image_ref="${docker_image_name}:${DOCKER_IMAGE_TAG}"
	fi
	local temp_workspace
	local payload_file

	if [[ -z "${GITHUB_ACTIONS:-}" ]]; then
		if [[ -z "${BRANCH:-}" ]]; then
			BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')
		fi

		if [[ -z "${COMMIT_SHA:-}" ]]; then
			COMMIT_SHA=$(git rev-parse HEAD 2>/dev/null || echo 'unknown')
		fi

		if [[ -z "${COMMIT_SHORT:-}" ]]; then
			COMMIT_SHORT="${COMMIT_SHA:0:7}"
		fi

		if [[ -z "${TIMESTAMP:-}" ]]; then
			TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
		fi

		if [[ -z "${REPO:-}" ]]; then
			local git_url
			git_url=$(git config --get remote.origin.url 2>/dev/null || echo '')
			if [[ -n "$git_url" ]]; then
				# Extract repo name from git URL, handling both https and ssh formats
				if [[ "$git_url" =~ github\.com[:/]([^/]+/[^/]+)\.git?$ ]]; then
					REPO="${BASH_REMATCH[1]}"
				elif [[ "$git_url" =~ github\.com[:/]([^/]+/[^/]+)/?$ ]]; then
					REPO="${BASH_REMATCH[1]}"
				else
					REPO="unknown"
				fi
			else
				REPO="unknown"
			fi
		fi
		export BRANCH COMMIT_SHA COMMIT_SHORT TIMESTAMP REPO
	fi

	# Create temporary workspace
	temp_workspace="$(mktemp -d)"
	trap 'rm -rf "$temp_workspace"' EXIT ERR

	local blocks_json
	blocks_json=$(jq -n \
		--arg branch "${BRANCH:-unknown}" \
		--arg commit "${COMMIT_SHORT:-unknown}" \
		--arg timestamp "${TIMESTAMP:-unknown}" \
		'[
			{
				type: "context",
				elements: [
					{
						type: "plain_text",
						text: "Branch: \($branch)"
					},
					{
						type: "plain_text",
						text: "Commit: \($commit)"
					},
					{
						type: "plain_text",
						text: "Time: \($timestamp)"
					}
				]
			},
			{
				type: "markdown",
				text: "The build test completed successfully."
			}
		]')

	# Add GitHub Actions context block if in GHA mode
	if [[ -n "${GITHUB_ACTIONS:-}" ]] && [[ -n "${EVENT_TYPE:-}" ]]; then
		local gha_context_block
		local elements_array
		elements_array=$(jq -n \
			--arg event_type "${EVENT_TYPE:-}" \
			'[{
				type: "plain_text",
				text: "Event: \($event_type)"
			}]')

		# Add workflow URL element if available
		if [[ -n "${WORKFLOW_RUN_URL:-}" ]]; then
			elements_array=$(echo "$elements_array" | jq \
				--arg workflow_url "${WORKFLOW_RUN_URL:-}" \
				'. += [{
					type: "plain_text",
					text: "Workflow: \($workflow_url)"
				}]')
		fi

		# Add PR info if available
		if [[ -n "${PR_NUMBER:-}" ]] && [[ -n "${PR_URL:-}" ]]; then
			elements_array=$(echo "$elements_array" | jq \
				--arg pr_number "${PR_NUMBER:-}" \
				'. += [{
					type: "plain_text",
					text: "PR: #\($pr_number)"
				}]')
		fi

		gha_context_block=$(jq -n \
			--argjson elements "$elements_array" \
			'{
				type: "context",
				elements: $elements
			}')

		# Insert GHA context block at the beginning (before the existing context block)
		blocks_json=$(echo "$blocks_json" | jq --argjson gha_block "$gha_context_block" '. |= [$gha_block] + .')
	fi

	# Create payload JSON
	payload_file=$(mktemp)
	trap 'rm -rf "$temp_workspace" "$payload_file"' EXIT ERR

	jq -n \
		--arg token "$SLACK_BOT_USER_OAUTH_TOKEN" \
		--argjson blocks "$blocks_json" \
		--arg channel "$CHANNEL" \
		'{
			source: {
				slack_bot_user_oauth_token: $token
			},
			params: {
				channel: $channel,
				dry_run: "false",
				blocks: $blocks
			}
		}' >"$payload_file"

	# Copy workspace files
	rsync -a --exclude='.git' "${GIT_ROOT}/" "${temp_workspace}/"
	cp "$payload_file" "${temp_workspace}/payload.json"

	# Run send-to-slack in container
	echo "Sending notification to channel: ${CHANNEL}"
	docker run --rm \
		--platform linux/amd64 \
		--entrypoint /bin/bash \
		-v "${temp_workspace}:/workspace" \
		-e CHANNEL="$CHANNEL" \
		-e SLACK_BOT_USER_OAUTH_TOKEN="$SLACK_BOT_USER_OAUTH_TOKEN" \
		-w /workspace \
		"$image_ref" \
		-c "
			cd /workspace && \
			send-to-slack < /workspace/payload.json
		"

	local exit_code=$?
	rm -rf "$temp_workspace"
	rm -f "$payload_file"
	trap - EXIT ERR

	return $exit_code
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

	if ! check_env; then
		return 1
	fi

	# Skip building if image ID is specified (user wants to use existing image)
	if [[ -z "${DOCKER_IMAGE_ID:-}" ]]; then
		if ! build_image; then
			return 1
		fi
	fi

	if ! send_notification; then
		return 1
	fi

	echo "Build test completed successfully"
	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
	exit $?
fi
