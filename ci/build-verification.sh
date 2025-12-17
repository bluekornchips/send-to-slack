#!/usr/bin/env bash
#
# Container build verification script for send-to-slack
# Verifies the built container works by sending a test notification
#
set -eo pipefail

DOCKER_IMAGE_TAG="${DOCKER_IMAGE_TAG:-local}"
DOCKER_IMAGE_ID="${DOCKER_IMAGE_ID:-}"
CHANNEL="${CHANNEL:-}"
SLACK_BOT_USER_OAUTH_TOKEN="${SLACK_BOT_USER_OAUTH_TOKEN:-}"
DOCKERFILE_TYPE="${DOCKERFILE_TYPE:-default}"

# Get the project root directory based on script location
GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
# Verify git root is the correct project, otherwise use script location
if [[ -z "$GIT_ROOT" ]] || [[ ! -f "${GIT_ROOT}/send-to-slack.sh" ]]; then
	GIT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fi

# Verify it's the correct directory by checking for expected files
if [[ ! -f "${GIT_ROOT}/send-to-slack.sh" ]]; then
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

Build the Docker image and verify the container works by sending a notification to Slack.

OPTIONS:
  -i, --image IMAGE_ID     Docker image ID to use for verification
  --remote                 Build and test using Docker/Dockerfile.remote
  --concourse              Build and test using Docker/Dockerfile.concourse
  -h, --help               Show this help message

ENVIRONMENT VARIABLES:
  CHANNEL                  Required: Slack channel to send notification to
  SLACK_BOT_USER_OAUTH_TOKEN  Required: Slack OAuth token
  DOCKER_IMAGE_NAME        Image name (default: send-to-slack)
  DOCKER_IMAGE_TAG         Image tag (default: local)
  DOCKER_IMAGE_ID          Image ID (overridden by -i/--image)

EXAMPLES:
  # Build and verify with default tag
  CHANNEL=#test SLACK_BOT_USER_OAUTH_TOKEN=token $0

  # Build and verify with custom tag via environment variable
  CHANNEL=#test SLACK_BOT_USER_OAUTH_TOKEN=token DOCKER_IMAGE_TAG=v1.0.0 $0

  # Build and verify using Dockerfile.remote
  CHANNEL=#test SLACK_BOT_USER_OAUTH_TOKEN=token $0 --remote

  # Build and verify using Dockerfile.concourse
  CHANNEL=#test SLACK_BOT_USER_OAUTH_TOKEN=token $0 --concourse

  # Verify using an existing image by ID
  CHANNEL=#test SLACK_BOT_USER_OAUTH_TOKEN=token $0 --image efa4fc963b0e
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
		-i | --image)
			if [[ -z "${2:-}" ]]; then
				echo "parse_args:: option $1 requires an argument" >&2
				return 1
			fi
			DOCKER_IMAGE_ID="$2"
			shift 2
			;;
		--remote)
			if [[ "$DOCKERFILE_TYPE" != "default" ]]; then
				echo "parse_args:: --remote and --concourse are mutually exclusive" >&2
				return 1
			fi
			DOCKERFILE_TYPE="remote"
			shift
			;;
		--concourse)
			if [[ "$DOCKERFILE_TYPE" != "default" ]]; then
				echo "parse_args:: --remote and --concourse are mutually exclusive" >&2
				return 1
			fi
			DOCKERFILE_TYPE="concourse"
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

# Build the image using build.sh or directly with docker build
#
# Returns:
# - 0 on success
# - 1 on failure
build_image() {
	local docker_image_name="${DOCKER_IMAGE_NAME:-send-to-slack}"
	local dockerfile_path
	local build_repo
	local build_branch

	# Determine which Dockerfile to use
	case "$DOCKERFILE_TYPE" in
	remote)
		dockerfile_path="${GIT_ROOT}/Docker/Dockerfile.remote"
		;;
	concourse)
		dockerfile_path="${GIT_ROOT}/Docker/Dockerfile.concourse"
		;;
	default)
		# Use build.sh for default Dockerfile
		local build_script="${GIT_ROOT}/ci/build.sh"

		if [[ ! -f "$build_script" ]]; then
			echo "build_image:: build.sh not found: $build_script" >&2
			return 1
		fi

		if [[ ! -x "$build_script" ]]; then
			chmod +x "$build_script"
		fi

		echo "Running build.sh to create Docker image."
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
		;;
	esac

	# Build directly using docker build for remote/concourse
	if [[ ! -f "$dockerfile_path" ]]; then
		echo "build_image:: Dockerfile not found: $dockerfile_path" >&2
		return 1
	fi

	# Get repo and branch from env vars, git, or defaults
	build_repo="${GITHUB_REPOSITORY:-}"
	build_branch="${GITHUB_HEAD_REF:-${GITHUB_REF_NAME:-}}"

	# Detect branch from git if not set and not in GitHub Actions
	if [[ -z "$build_branch" ]] && [[ -z "${GITHUB_ACTIONS:-}" ]] && command -v git >/dev/null 2>&1; then
		build_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')
	fi

	if [[ -z "$build_repo" ]] && command -v git >/dev/null 2>&1; then
		local git_url
		git_url=$(git config --get remote.origin.url 2>/dev/null || echo '')
		if [[ "$git_url" =~ github\.com[:/]([^/]+/[^/]+) ]]; then
			build_repo="${BASH_REMATCH[1]}"
		fi
	fi

	build_repo="${build_repo:-bluekornchips/send-to-slack}"
	build_branch="${build_branch:-main}"

	# Display detected values for remote builds
	if [[ "$DOCKERFILE_TYPE" == "remote" ]]; then
		echo "build_image:: detected repository: ${build_repo}"
		echo "build_image:: detected branch: ${build_branch}"
	fi

	local image_ref
	if [[ "$DOCKER_IMAGE_TAG" == *:* ]]; then
		image_ref="$DOCKER_IMAGE_TAG"
	else
		image_ref="${docker_image_name}:${DOCKER_IMAGE_TAG}"
	fi

	echo "Building Docker image ${image_ref} from ${dockerfile_path}."
	cd "${GIT_ROOT}" || return 1

	local docker_build_args=(
		--platform linux/amd64
		-t "$image_ref"
		-f "$dockerfile_path"
	)

	# Add build args for remote Dockerfile
	if [[ "$DOCKERFILE_TYPE" == "remote" ]]; then
		docker_build_args+=(
			--build-arg "GITHUB_REPOSITORY=${build_repo}"
			--build-arg "GITHUB_REF_NAME=${build_branch}"
		)
		echo "build_image:: passing build args: GITHUB_REPOSITORY=${build_repo}, GITHUB_REF_NAME=${build_branch}"
	fi

	# Use no-cache by default
	docker_build_args+=(--no-cache)

	if ! docker build "${docker_build_args[@]}" .; then
		echo "build_image:: failed to build Docker image" >&2
		return 1
	fi

	echo "Successfully built ${image_ref}"
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

	# Build context block with Event and Date
	local context_block
	context_block=$(jq -n \
		--arg event_type "${EVENT_TYPE:-Build}" \
		--arg timestamp "${TIMESTAMP:-unknown}" \
		'{
			type: "context",
			elements: [
				{
					type: "plain_text",
					text: "Event: \($event_type)"
				},
				{
					type: "plain_text",
					text: "Date: \($timestamp)"
				}
			]
		}')

	local table_block
	local pr_url="${PR_URL:-}"
	local branch_url=""
	local commit_url=""
	local workflow_url="${WORKFLOW_RUN_URL:-}"

	if [[ -n "${REPO:-}" ]] && [[ "${REPO:-}" != "unknown" ]]; then
		if [[ -n "${BRANCH:-}" ]] && [[ "${BRANCH:-}" != "unknown" ]]; then
			branch_url="https://github.com/${REPO}/tree/${BRANCH}"
		fi
		if [[ -n "${COMMIT_SHA:-}" ]] && [[ "${COMMIT_SHA:-}" != "unknown" ]]; then
			commit_url="https://github.com/${REPO}/commit/${COMMIT_SHA}"
		fi
	fi

	# Build table rows with rich_text cells
	local table_rows
	table_rows=$(jq -n \
		--arg pr_url "$pr_url" \
		--arg pr_number "${PR_NUMBER:-}" \
		--arg branch_url "$branch_url" \
		--arg branch "${BRANCH:-unknown}" \
		--arg commit_url "$commit_url" \
		--arg commit "${COMMIT_SHORT:-unknown}" \
		--arg workflow_url "$workflow_url" \
		'[
			[
				{
					type: "rich_text",
					elements: [
						{
							type: "rich_text_section",
							elements: (if $pr_url != "" then [{
								type: "link",
								url: $pr_url,
								text: (if $pr_number != "" then "#\($pr_number)" else "PR" end)
							}] else [{
								type: "text",
								text: (if $pr_number != "" then "#\($pr_number)" else "N/A" end)
							}] end)
						}
					]
				},
				{
					type: "rich_text",
					elements: [
						{
							type: "rich_text_section",
							elements: (if $branch_url != "" then [{
								type: "link",
								url: $branch_url,
								text: $branch
							}] else [{
								type: "text",
								text: $branch
							}] end)
						}
					]
				}
			],
			[
				{
					type: "rich_text",
					elements: [
						{
							type: "rich_text_section",
							elements: (if $commit_url != "" then [{
								type: "link",
								url: $commit_url,
								text: $commit
							}] else [{
								type: "text",
								text: $commit
							}] end)
						}
					]
				},
				{
					type: "rich_text",
					elements: [
						{
							type: "rich_text_section",
							elements: (if $workflow_url != "" then [{
								type: "link",
								url: $workflow_url,
								text: "View Workflow"
							}] else [{
								type: "text",
								text: "N/A"
							}] end)
						}
					]
				}
			]
		]')

	# Create table block
	table_block=$(jq -n \
		--argjson rows "$table_rows" \
		'{
			type: "table",
			rows: $rows
		}')

	# Combine blocks: context block, then table block, then success message
	local blocks_json
	blocks_json=$(jq -n \
		--argjson context "$context_block" \
		--argjson table "$table_block" \
		'[
			$context,
			$table,
			{
				type: "markdown",
				text: "The build verification completed successfully."
			}
		]')

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

	# Determine the correct path to send-to-slack based on Dockerfile type
	local send_to_slack_cmd
	case "$DOCKERFILE_TYPE" in
	concourse)
		# Concourse Dockerfile installs to /opt/resource/send-to-slack and adds /opt/resource to PATH
		send_to_slack_cmd="send-to-slack"
		;;
	*)
		# Default and remote Dockerfiles install to /usr/local/bin
		send_to_slack_cmd="/usr/local/bin/send-to-slack"
		;;
	esac

	docker run --rm \
		--platform linux/amd64 \
		-v "${temp_workspace}:/workspace" \
		-e CHANNEL="${CHANNEL}" \
		-e SLACK_BOT_USER_OAUTH_TOKEN="${SLACK_BOT_USER_OAUTH_TOKEN}" \
		-w /workspace \
		"$image_ref" \
		"$send_to_slack_cmd" -f /workspace/payload.json

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

	echo "Build verification completed successfully"
	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
	exit $?
fi
