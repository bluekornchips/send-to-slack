#!/usr/bin/env bash
#
# Installation script for send-to-slack
# Installs send-to-slack to the specified prefix directory
# Supports curl | bash installation.
#
set -euo pipefail
IFS=$' \n\t'

VERSION_FILE_NAME="VERSION"
DEFAULT_INSTALL_PATH="${HOME:+${HOME}/.local}"
DEFAULT_REPO_URL="https://github.com/bluekornchips/send-to-slack"
DEFAULT_REPO_BRANCH="main"
CLEANUP_ROOT=""
RESOLVED_REF=""
INSTALL_MODE=""
COMMIT_REF=""
prefix=""

# Network configuration
CURL_TIMEOUT=30
CURL_MAX_RETRIES=3
CURL_RETRY_DELAY=2

# Display usage information
#
# Side Effects:
# - Outputs usage message to stderr
usage() {
	cat <<EOF >&2
usage: $0 [OPTIONS]

Install send-to-slack to the specified prefix directory.

OPTIONS:
  --local              Install from local git repository (auto-detected when run from file in git repo)
  --commit <ref>       Install from specific tag or commit SHA
  --path <prefix>      Installation prefix (default: ~/.local)
  -h, --help           Show this help message

When run without options:
  - In git repository: automatically uses --local
  - Otherwise: automatically installs latest from main branch

ENVIRONMENT VARIABLES:
  SEND_TO_SLACK_REPO_URL    Override repository URL (default: ${DEFAULT_REPO_URL})

EXAMPLES:
  # Install latest from main branch
  curl -fsSL https://raw.githubusercontent.com/bluekornchips/send-to-slack/main/install.sh | bash

  # Install specific commit
  curl -fsSL https://raw.githubusercontent.com/bluekornchips/send-to-slack/main/install.sh | bash -s -- --commit v0.1.2

  # Install from local repository
  ./install.sh --local

  # Install to custom prefix
  ./install.sh --path /opt
EOF
}

# Remove temporary working directory when present
#
# Returns:
# - 0 always
cleanup() {
	if [[ -n "$CLEANUP_ROOT" && -d "$CLEANUP_ROOT" ]]; then
		rm -rf "$CLEANUP_ROOT"
	fi

	return 0
}

trap cleanup EXIT

# Ensure required commands exist
#
# Inputs:
# - $@ - commands to verify
#
# Returns:
# - 0 when all commands exist
# - 1 when a command is missing
require_commands() {
	local cmd

	for cmd in "$@"; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			echo "require_commands:: missing required command: ${cmd}" >&2
			return 1
		fi
	done

	return 0
}

# Download URL with retry and timeout
#
# Inputs:
# - $1 - url: URL to download
# - $2 - output: Output file path
#
# Returns:
# - 0 on success
# - 1 on failure
download_with_retry() {
	local url="$1"
	local output="$2"
	local curl_opts=(
		-fsSL
		--connect-timeout "$CURL_TIMEOUT"
		--max-time "$((CURL_TIMEOUT * 3))"
		--retry "$CURL_MAX_RETRIES"
		--retry-delay "$CURL_RETRY_DELAY"
		--retry-all-errors
		-o "$output"
	)

	if [[ -n "${HTTP_PROXY:-}" ]] || [[ -n "${HTTPS_PROXY:-}" ]] || [[ -n "${http_proxy:-}" ]] || [[ -n "${https_proxy:-}" ]]; then
		curl_opts+=(--proxy "${HTTPS_PROXY:-${https_proxy:-${HTTP_PROXY:-${http_proxy:-}}}}}")
	fi

	if curl "${curl_opts[@]}" "$url"; then
		return 0
	fi

	echo "download_with_retry:: failed to download ${url} after ${CURL_MAX_RETRIES} attempts" >&2
	return 1
}

# Verify SHA256 checksum
#
# Inputs:
# - $1 - file_path: Path to file to verify
# - $2 - expected_hash: Expected SHA256 hash
#
# Returns:
# - 0 on match
# - 1 on mismatch or error
verify_checksum() {
	local file_path="$1"
	local expected_hash="$2"
	local actual_hash

	if [[ ! -f "$file_path" ]]; then
		echo "verify_checksum:: file not found: ${file_path}" >&2
		return 1
	fi

	if command -v sha256sum >/dev/null 2>&1; then
		actual_hash=$(sha256sum "$file_path" | cut -d' ' -f1)
	elif command -v shasum >/dev/null 2>&1; then
		actual_hash=$(shasum -a 256 "$file_path" | cut -d' ' -f1)
	else
		echo "verify_checksum:: no sha256 tool available" >&2
		return 1
	fi

	if [[ "$actual_hash" != "$expected_hash" ]]; then
		echo "verify_checksum:: checksum mismatch for ${file_path}" >&2
		echo "verify_checksum:: expected: ${expected_hash}" >&2
		echo "verify_checksum:: actual: ${actual_hash}" >&2
		return 1
	fi

	return 0
}

# Fetch checksum for a given ref from GitHub releases or checksums file
#
# Inputs:
# - $1 - ref: Git reference (tag or commit)
#
# Outputs:
# - Writes checksum to stdout on success
#
# Returns:
# - 0 on success
# - 1 on failure
fetch_checksum() {
	local ref="$1"
	local repo_url="${SEND_TO_SLACK_REPO_URL:-$DEFAULT_REPO_URL}"
	local checksum_url
	local temp_file
	local checksum

	repo_url="${repo_url%.git}"
	checksum_url="${repo_url}/releases/download/${ref}/checksums.sha256"

	temp_file=$(mktemp -t install.XXXXXX)
	CLEANUP_ROOT="${CLEANUP_ROOT:-$(dirname "$temp_file")}"

	if ! download_with_retry "$checksum_url" "$temp_file" 2>/dev/null; then
		rm -f "$temp_file"
		return 1
	fi

	if [[ -f "$temp_file" ]]; then
		checksum=$(grep -E "\.tar\.gz$" "$temp_file" | awk '{print $1}' | head -n1)
		rm -f "$temp_file"
		if [[ -n "$checksum" ]]; then
			echo "$checksum"
			return 0
		fi
	fi

	return 1
}

# Download and unpack GitHub tarball
#
# Inputs:
# - $1 - ref: Git reference (tag or commit SHA)
#
# Outputs:
# - Writes extracted root path to stdout on success
#
# Returns:
# - 0 on success
# - 1 on failure
download_and_unpack() {
	local ref="$1"
	local repo_url="${SEND_TO_SLACK_REPO_URL:-$DEFAULT_REPO_URL}"
	local tarball_url
	local temp_dir
	local tarball_file
	local extracted_root
	local expected_checksum

	repo_url="${repo_url%.git}"

	if [[ "$ref" =~ ^[0-9a-f]{40}$ ]]; then
		tarball_url="${repo_url}/archive/${ref}.tar.gz"
	else
		tarball_url="${repo_url}/archive/refs/tags/${ref}.tar.gz"
	fi

	temp_dir=$(mktemp -dt install.XXXXXX)
	CLEANUP_ROOT="$temp_dir"
	tarball_file="${temp_dir}/source.tar.gz"

	if ! download_with_retry "$tarball_url" "$tarball_file"; then
		echo "download_and_unpack:: failed to download tarball" >&2
		return 1
	fi

	if expected_checksum=$(fetch_checksum "$ref"); then
		if ! verify_checksum "$tarball_file" "$expected_checksum"; then
			echo "download_and_unpack:: checksum verification failed" >&2
			return 1
		fi
	fi

	if ! require_commands tar; then
		echo "download_and_unpack:: tar command not found" >&2
		return 1
	fi

	if ! tar -xzf "$tarball_file" -C "$temp_dir"; then
		echo "download_and_unpack:: failed to extract tarball" >&2
		return 1
	fi

	extracted_root=$(find "$temp_dir" -maxdepth 1 -type d -name "send-to-slack-*" | head -n1)
	if [[ -z "$extracted_root" ]]; then
		extracted_root=$(find "$temp_dir" -maxdepth 1 -type d ! -path "$temp_dir" | head -n1)
	fi

	if [[ -z "$extracted_root" || ! -d "$extracted_root" ]]; then
		echo "download_and_unpack:: failed to locate extracted directory" >&2
		return 1
	fi

	echo "$extracted_root"
	return 0
}

# Get latest commit SHA from main branch
#
# Outputs:
# - Writes commit SHA to stdout on success
#
# Returns:
# - 0 on success
# - 1 on failure
get_latest_main_commit() {
	local repo_url="${SEND_TO_SLACK_REPO_URL:-$DEFAULT_REPO_URL}"
	local api_url
	local temp_file
	local commit_sha

	repo_url="${repo_url%.git}"
	api_url="${repo_url/github.com/api.github.com/repos}/commits/${DEFAULT_REPO_BRANCH}"

	temp_file=$(mktemp -t install.XXXXXX)
	CLEANUP_ROOT="${CLEANUP_ROOT:-$(dirname "$temp_file")}"

	if ! download_with_retry "$api_url" "$temp_file" 2>/dev/null; then
		rm -f "$temp_file"
		echo "HEAD"
		return 0
	fi

	if command -v jq >/dev/null 2>&1 && [[ -f "$temp_file" ]]; then
		commit_sha=$(jq -r '.sha' "$temp_file" 2>/dev/null)
		rm -f "$temp_file"
		if [[ -n "$commit_sha" && "$commit_sha" != "null" ]]; then
			echo "$commit_sha"
			return 0
		fi
	fi

	rm -f "$temp_file"
	echo "HEAD"
	return 0
}

# Validate installation prerequisites
#
# Inputs:
# - $1 - script_root: Root directory containing send-to-slack.sh and bin/
#
# Returns:
# - 0 if all prerequisites are met
# - 1 if prerequisites are missing
validate_prerequisites() {
	local script_root="$1"

	if [[ ! -f "$script_root/send-to-slack.sh" ]]; then
		echo "validate_prerequisites:: main script not found: ${script_root}/send-to-slack.sh" >&2
		return 1
	fi

	if [[ ! -d "$script_root/bin" ]]; then
		echo "validate_prerequisites:: bin directory not found: ${script_root}/bin" >&2
		return 1
	fi

	return 0
}

# Resolve version string from a repo
#
# Inputs:
# - $1 - repo_root: Local repository path
# - $2 - ref: Git reference (optional, defaults to HEAD)
#
# Outputs:
# - Writes version string to stdout on success
#
# Returns:
# - 0 on success
# - 1 on failure
get_version_from_repo() {
	local repo_root="$1"
	local ref="${2:-HEAD}"
	local version_value

	if [[ -f "${repo_root}/${VERSION_FILE_NAME}" ]]; then
		version_value=$(tr -d '\r' <"${repo_root}/${VERSION_FILE_NAME}" | tr -d '\n')
		if [[ -n "$version_value" ]]; then
			echo "$version_value"
			return 0
		fi
	fi

	if command -v git >/dev/null 2>&1 && [[ -d "${repo_root}/.git" ]]; then
		if version_value=$(git -C "$repo_root" show "${ref}:${VERSION_FILE_NAME}" 2>/dev/null); then
			version_value=$(echo "$version_value" | tr -d '\r' | tr -d '\n')
			if [[ -n "$version_value" ]]; then
				echo "$version_value"
				return 0
			fi
		fi
	fi

	echo "$ref"
	return 0
}

# Perform the installation
#
# Inputs:
# - $1 - script_root: Root directory containing send-to-slack.sh and bin/
# - $2 - prefix: Installation prefix directory
# - $3 - manifest_file: Manifest recording installed files
#
# Returns:
# - 0 on success
# - 1 on failure
install_files() {
	local script_root="$1"
	local prefix="$2"
	local manifest_file="$3"
	local manifest_dir
	local manifest_entries=()

	install -d -m 755 "$prefix/bin/blocks"
	manifest_dir=$(dirname "$manifest_file")
	install -d -m 755 "$manifest_dir"

	install -m 755 "$script_root/send-to-slack.sh" "$prefix/bin/send-to-slack"
	manifest_entries+=("$prefix/bin/send-to-slack")

	for file in "$script_root/bin"/*; do
		if [[ -f "$file" ]]; then
			install -m 755 "$file" "$prefix/bin/"
			manifest_entries+=("$prefix/bin/$(basename "$file")")
		fi
	done

	for file in "$script_root/bin/blocks"/*; do
		if [[ -f "$file" ]]; then
			install -m 755 "$file" "$prefix/bin/blocks/"
			manifest_entries+=("$prefix/bin/blocks/$(basename "$file")")
		fi
	done

	if [[ -f "${script_root}/${VERSION_FILE_NAME}" ]]; then
		install -m 644 "${script_root}/${VERSION_FILE_NAME}" "$prefix/share/send-to-slack/${VERSION_FILE_NAME}"
		manifest_entries+=("$prefix/share/send-to-slack/${VERSION_FILE_NAME}")
	fi

	printf '%s\n' "${manifest_entries[@]}" >"$manifest_file"

	return 0
}

# Resolve script root from local git repository
#
# Outputs:
# - Writes script root path to stdout on success
#
# Returns:
# - 0 on success
# - 1 on failure
resolve_local_script_root() {
	local repo_root

	if ! require_commands git; then
		echo "resolve_local_script_root:: git command not found" >&2
		return 1
	fi

	if ! repo_root=$(git rev-parse --show-toplevel 2>/dev/null); then
		echo "resolve_local_script_root:: not in a git repository" >&2
		return 1
	fi

	echo "$repo_root"
	return 0
}

# Resolve script root from remote ref (tag or commit)
#
# Inputs:
# - $1 - ref: Git reference (tag or commit SHA)
#
# Outputs:
# - Writes script root path to stdout on success
#
# Returns:
# - 0 on success
# - 1 on failure
resolve_remote_script_root() {
	local ref="$1"
	local script_root

	if ! require_commands curl tar; then
		echo "resolve_remote_script_root:: required commands not found (curl, tar)" >&2
		return 1
	fi

	if ! script_root=$(download_and_unpack "$ref"); then
		echo "resolve_remote_script_root:: failed to download and unpack ${ref}" >&2
		return 1
	fi

	echo "$script_root"
	return 0
}

# Perform installation from resolved script root
#
# Inputs:
# - $1 - script_root: Root directory containing send-to-slack.sh and bin/
# - $2 - ref: Git reference for version resolution
# - $3 - prefix: Installation prefix directory
#
# Returns:
# - 0 on success
# - 1 on failure
perform_installation() {
	local script_root="$1"
	local ref="$2"
	local prefix="$3"
	local manifest_file
	local resolved_version

	if ! validate_prerequisites "$script_root"; then
		return 1
	fi

	manifest_file="$prefix/share/send-to-slack/install_manifest.txt"

	if ! install_files "$script_root" "$prefix" "$manifest_file"; then
		return 1
	fi

	resolved_version=$(get_version_from_repo "$script_root" "$ref")
	mkdir -p "$prefix/share/send-to-slack"
	printf '%s\n' "$resolved_version" >"$prefix/share/send-to-slack/${VERSION_FILE_NAME}"

	return 0
}

# Install from local git repository
#
# Inputs:
# - $1 - prefix: Installation prefix directory
#
# Returns:
# - 0 on success
# - 1 on failure
install_local() {
	local prefix="$1"
	local script_root
	local repo_root

	if ! script_root=$(resolve_local_script_root); then
		return 1
	fi

	repo_root="$script_root"
	RESOLVED_REF=$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || echo "local")

	if ! perform_installation "$script_root" "HEAD" "$prefix"; then
		return 1
	fi

	return 0
}

# Install from specific commit
#
# Inputs:
# - $1 - ref: Git reference (tag or commit SHA)
# - $2 - prefix: Installation prefix directory
#
# Returns:
# - 0 on success
# - 1 on failure
install_commit() {
	local ref="$1"
	local prefix="$2"
	local script_root

	if ! script_root=$(resolve_remote_script_root "$ref"); then
		return 1
	fi

	RESOLVED_REF="$ref"

	if ! perform_installation "$script_root" "$ref" "$prefix"; then
		return 1
	fi

	return 0
}

# Install latest from main branch
#
# Inputs:
# - $1 - prefix: Installation prefix directory
#
# Returns:
# - 0 on success
# - 1 on failure
install_latest_main() {
	local prefix="$1"
	local latest_ref
	local script_root

	latest_ref=$(get_latest_main_commit)

	if ! script_root=$(resolve_remote_script_root "$latest_ref"); then
		echo "install_latest_main:: failed to download and unpack latest" >&2
		return 1
	fi

	RESOLVED_REF="$latest_ref"

	if ! perform_installation "$script_root" "$latest_ref" "$prefix"; then
		return 1
	fi

	return 0
}

# Auto-detect installation mode based on execution context
#
# Side Effects:
# - Sets INSTALL_MODE if not already set
auto_detect_install_mode() {
	if [[ -n "$INSTALL_MODE" ]]; then
		return 0
	fi

	if command -v git >/dev/null 2>&1 && git rev-parse HEAD >/dev/null 2>&1; then
		INSTALL_MODE="local"
	else
		INSTALL_MODE="latest"
	fi

	return 0
}

# Parse command line arguments
#
# Inputs:
# - $@ - command line arguments
#
# Side Effects:
# - Sets INSTALL_MODE, prefix (global), COMMIT_REF (global) variables
#
# Returns:
# - 0 on success
# - 1 on failure
parse_args() {
	local commit_ref=""

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--local)
			if [[ -n "$INSTALL_MODE" ]]; then
				echo "parse_args:: --local cannot be used with other install modes" >&2
				return 1
			fi
			INSTALL_MODE="local"
			shift
			;;
		--commit)
			if [[ -n "$INSTALL_MODE" ]]; then
				echo "parse_args:: --commit cannot be used with other install modes" >&2
				return 1
			fi
			if [[ $# -lt 2 ]]; then
				echo "parse_args:: --commit requires a value" >&2
				return 1
			fi
			INSTALL_MODE="commit"
			commit_ref="$2"
			shift 2
			;;
		--path)
			if [[ $# -lt 2 ]]; then
				echo "parse_args:: --path requires a value" >&2
				return 1
			fi
			prefix="${2%/}"
			shift 2
			;;
		-h | --help)
			usage
			return 2
			;;
		-*)
			echo "parse_args:: unknown option: $1" >&2
			return 1
			;;
		*)
			if [[ -z "$prefix" ]]; then
				prefix="${1%/}"
			else
				echo "parse_args:: unexpected argument: $1" >&2
				return 1
			fi
			shift
			;;
		esac
	done

	auto_detect_install_mode

	if [[ "$INSTALL_MODE" == "commit" && -z "$commit_ref" ]]; then
		echo "parse_args:: --commit requires a reference" >&2
		return 1
	fi

	COMMIT_REF="$commit_ref"
	return 0
}

# Main entry point
#
# Inputs:
# - CLI flags
#
# Returns:
# - 0 on success
# - 1 on failure
main() {
	local script_root
	local default_prefix
	local parse_result

	default_prefix="$DEFAULT_INSTALL_PATH"

	prefix=""
	INSTALL_MODE=""
	COMMIT_REF=""

	parse_result=0
	parse_args "$@" || parse_result=$?

	if [[ $parse_result -eq 2 ]]; then
		return 0
	fi

	if [[ $parse_result -ne 0 ]]; then
		usage
		return 1
	fi

	if [[ -z "$prefix" ]]; then
		prefix="$default_prefix"
	fi

	if [[ "$prefix" == ~* ]] && [[ -n "$HOME" ]]; then
		prefix="${prefix/#\~/$HOME}"
	fi

	case "$INSTALL_MODE" in
	local)
		if ! install_local "$prefix"; then
			return 1
		fi
		;;
	commit)
		if ! install_commit "$COMMIT_REF" "$prefix"; then
			return 1
		fi
		;;
	latest)
		if ! install_latest_main "$prefix"; then
			return 1
		fi
		;;
	*)
		echo "main:: unknown install mode: ${INSTALL_MODE}" >&2
		return 1
		;;
	esac

	echo "Installed send-to-slack to ${prefix}/bin/send-to-slack"
	echo "Resolved reference: ${RESOLVED_REF}"

	return 0
}

# Only run main when script is executed directly, not when sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
	exit $?
fi
