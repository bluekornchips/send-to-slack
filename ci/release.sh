#!/usr/bin/env bash
#
# Release script for send-to-slack
# Creates release tarballs for distribution
#
set -eo pipefail

ARTIFACT_VERSION="${ARTIFACT_VERSION:-}"
ARTIFACT_OUTPUT="${ARTIFACT_OUTPUT:-./artifacts}"

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
usage() {
	cat <<EOF
usage: $0 [OPTIONS]

Build release tarballs for send-to-slack distribution.

OPTIONS:
  --version <tag>     Version tag for artifact (e.g., v0.1.3). Default: read from VERSION file
  --output <dir>      Output directory for artifacts (default: ./artifacts)
  --dry-run           Show what would be created without actually creating it
  -h, --help          Show this help message

ENVIRONMENT VARIABLES:
  ARTIFACT_VERSION    Version tag (alternative to --version)
  ARTIFACT_OUTPUT     Output directory (alternative to --output)

EXAMPLES:
  # Build artifact using VERSION file
  $0

  # Build artifact with explicit version
  $0 --version v0.1.3

  # Build artifact to custom directory
  $0 --version v0.1.3 --output ./release

  # Dry run to see what would be created
  $0 --dry-run
EOF
	return 0
}

# Check for required external commands
check_dependencies() {
	local missing_deps=()
	local required_commands=("tar" "cp" "mkdir" "mktemp")

	for cmd in "${required_commands[@]}"; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			missing_deps+=("$cmd")
		fi
	done

	if [[ ${#missing_deps[@]} -gt 0 ]]; then
		echo "check_dependencies:: missing required dependencies: ${missing_deps[*]}" >&2
		return 1
	fi

	return 0
}

# Get version from argument or VERSION file
#
# Inputs:
# - $1 - version (optional, reads from VERSION if empty)
#
# Outputs:
# - Writes version string to stdout
#
# Returns:
# - 0 on success, 1 on failure
get_version() {
	local version_arg="${1:-}"
	local version_file="${GIT_ROOT}/VERSION"

	if [[ -n "$version_arg" ]]; then
		# Ensure version starts with 'v'
		if [[ "$version_arg" != v* ]]; then
			echo "v${version_arg}"
		else
			echo "$version_arg"
		fi
		return 0
	fi

	if [[ -f "$version_file" ]]; then
		local version_value
		version_value=$(tr -d '\r\n' <"$version_file")
		if [[ -n "$version_value" ]]; then
			echo "v${version_value}"
			return 0
		fi
	fi

	echo "get_version:: could not determine version" >&2
	return 1
}

# Detect OS and architecture
#
# Outputs:
# - Writes os_arch string to stdout (e.g., linux_amd64, darwin_amd64)
#
# Returns:
# - 0 on success, 1 on unsupported platform
detect_os_arch() {
	local os
	local arch

	os=$(uname -s | tr '[:upper:]' '[:lower:]')
	case "$os" in
	linux | darwin) ;;
	*)
		echo "detect_os_arch:: unsupported OS: $os" >&2
		return 1
		;;
	esac

	arch=$(uname -m | tr '[:upper:]' '[:lower:]')
	case "$arch" in
	x86_64 | amd64)
		arch="amd64"
		;;
	arm64 | aarch64)
		arch="arm64"
		;;
	*)
		echo "detect_os_arch:: unsupported architecture: $arch" >&2
		return 1
		;;
	esac

	echo "${os}_${arch}"
	return 0
}

# Build a release tarball
#
# Inputs:
# - $1 - version (e.g., v0.1.3)
# - $2 - output directory
# - $3 - dry_run flag (optional, "true" to skip actual creation)
#
# Returns:
# - 0 on success, 1 on failure
build_tarball() {
	local version="$1"
	local output_dir="$2"
	local dry_run="${3:-false}"
	local os_arch
	local tarball_name
	local staging_dir
	local version_stripped

	if [[ -z "$version" ]]; then
		echo "build_tarball:: version is required" >&2
		return 1
	fi

	if [[ -z "$output_dir" ]]; then
		echo "build_tarball:: output directory is required" >&2
		return 1
	fi

	if ! os_arch=$(detect_os_arch); then
		return 1
	fi

	# Strip leading 'v' for tarball naming
	version_stripped="${version#v}"
	tarball_name="send-to-slack_${version_stripped}_${os_arch}.tar.gz"

	if [[ "$dry_run" == "true" ]]; then
		echo "build_tarball:: [DRY RUN] would create ${output_dir}/${tarball_name}"
		echo "build_tarball:: [DRY RUN] contents:"
		echo "  - bin/send-to-slack.sh"
		echo "  - bin/install.sh"
		echo "  - bin/uninstall.sh"
		echo "  - lib/ (block helpers)"
		echo "  - VERSION"
		echo "  - LICENSE"
		echo "  - README.md"
		return 0
	fi

	echo "build_tarball:: creating ${tarball_name}"

	# Create output directory
	if ! mkdir -p "$output_dir"; then
		echo "build_tarball:: failed to create output directory: $output_dir" >&2
		return 1
	fi

	# Create staging directory
	staging_dir=$(mktemp -d)
	local package_dir="${staging_dir}/send-to-slack"

	if ! mkdir -p "$package_dir"; then
		echo "build_tarball:: failed to create staging directory" >&2
		rm -rf "$staging_dir"
		return 1
	fi

	# Copy files to staging
	if ! cp -r "${GIT_ROOT}/bin" "$package_dir/"; then
		echo "build_tarball:: failed to copy bin directory" >&2
		rm -rf "$staging_dir"
		return 1
	fi

	if ! cp -r "${GIT_ROOT}/lib" "$package_dir/"; then
		echo "build_tarball:: failed to copy lib directory" >&2
		rm -rf "$staging_dir"
		return 1
	fi

	if ! cp "${GIT_ROOT}/VERSION" "$package_dir/"; then
		echo "build_tarball:: failed to copy VERSION file" >&2
		rm -rf "$staging_dir"
		return 1
	fi

	if ! cp "${GIT_ROOT}/LICENSE" "$package_dir/" 2>/dev/null; then
		echo "build_tarball:: warning: LICENSE file not found, skipping"
	fi

	if ! cp "${GIT_ROOT}/README.md" "$package_dir/" 2>/dev/null; then
		echo "build_tarball:: warning: README.md file not found, skipping"
	fi

	# Create tarball
	if ! tar -czf "${output_dir}/${tarball_name}" -C "$staging_dir" send-to-slack; then
		echo "build_tarball:: failed to create tarball" >&2
		rm -rf "$staging_dir"
		return 1
	fi

	rm -rf "$staging_dir"

	echo "build_tarball:: created ${output_dir}/${tarball_name}"
	return 0
}

# Parse command line arguments
parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--version)
			shift
			if [[ -z "${1:-}" ]]; then
				echo "parse_args:: option --version requires an argument" >&2
				return 1
			fi
			ARTIFACT_VERSION="$1"
			shift
			;;
		--output)
			shift
			if [[ -z "${1:-}" ]]; then
				echo "parse_args:: option --output requires an argument" >&2
				return 1
			fi
			ARTIFACT_OUTPUT="$1"
			shift
			;;
		--dry-run)
			DRY_RUN="true"
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

# Main entry point
main() {
	local parse_result
	local resolved_version

	DRY_RUN="${DRY_RUN:-false}"

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

	if ! resolved_version=$(get_version "$ARTIFACT_VERSION"); then
		return 1
	fi

	echo "release:: version: ${resolved_version}"
	echo "release:: output: ${ARTIFACT_OUTPUT}"

	if ! build_tarball "$resolved_version" "$ARTIFACT_OUTPUT" "$DRY_RUN"; then
		return 1
	fi

	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
	exit $?
fi
