#!/usr/bin/env bash
#
# Installation script for send-to-slack
# Installs send-to-slack from GitHub tarball to the specified prefix directory
# Supports curl | bash installation.
#
set -euo pipefail
IFS=$' \n\t'

# Fail fast with a concise message when not using bash
# Single brackets for POSIX yo
if [ -z "${BASH_VERSION:-}" ]; then
	# Use echo here since abort() may not be defined yet if bash isn't running
	echo "Bash is required to interpret this script." >&2
	exit 1
fi

# Check bash version - requires 3.1+ for BASH_SOURCE array support
# Note: BASH_VERSINFO may not be available in very old bash versions
if [[ -n "${BASH_VERSINFO[0]:-}" ]]; then
	if [[ "${BASH_VERSINFO[0]}" -lt 3 ]] || [[ "${BASH_VERSINFO[0]}" -eq 3 && "${BASH_VERSINFO[1]:-0}" -lt 1 ]]; then
		echo "Bash 3.1 or later is required (current version: ${BASH_VERSION})" >&2
		exit 1
	fi
fi

# Check if script is run in POSIX mode
if [[ -n "${POSIXLY_CORRECT+1}" ]]; then
	echo "Bash must not run in POSIX mode. Please unset POSIXLY_CORRECT and try again." >&2
	exit 1
fi

VERSION_FILE_NAME="VERSION"
DEFAULT_REPO_URL="https://github.com/bluekornchips/send-to-slack"
DEFAULT_REPO_BRANCH="main"
CLEANUP_ROOT=""
RESOLVED_REF=""

# Network configuration
CURL_TIMEOUT=30
CURL_MAX_RETRIES=3
CURL_RETRY_DELAY=2

# Abort with error message
#
# Inputs:
# - $@ - error message(s) to display
#
# Side Effects:
# - Outputs error message(s) to stderr
# - Exits with status 1
abort() {
	printf "%s\n" "$@" >&2
	exit 1
}

# Display usage information
#
# Side Effects:
# - Outputs usage message to stderr
usage() {
	cat <<EOF >&2
usage: $0 [OPTIONS]

Install send-to-slack from GitHub tarball.
- Installs to ~/.local when run without sudo (default)
- Installs to /usr/local when run with sudo

OPTIONS:
  -h, --help         Show this help message

ENVIRONMENT VARIABLES:
  SEND_TO_SLACK_REPO_URL    Override repository URL (default: ${DEFAULT_REPO_URL})

EXAMPLES:
  # Install to ~/.local (no sudo required)
  curl -fsSL https://raw.githubusercontent.com/bluekornchips/send-to-slack/main/bin/install.sh | bash

  # Install to /usr/local (requires sudo)
  curl -fsSL https://raw.githubusercontent.com/bluekornchips/send-to-slack/main/bin/install.sh | sudo bash
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

# Check if running as root
#
# Returns:
# - 0 if running as root
# - 1 if not running as root
is_root() {
	if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
		return 0
	fi
	return 1
}

# Determine installation prefix based on whether running as root
#
# Outputs:
# - Writes installation prefix to stdout
#
# Returns:
# - 0 always
determine_install_prefix() {
	if is_root; then
		echo "/usr/local"
	else
		echo "${HOME}/.local"
	fi
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

	if curl -fsSL \
		--connect-timeout "$CURL_TIMEOUT" \
		--max-time "$((CURL_TIMEOUT * 3))" \
		--retry "$CURL_MAX_RETRIES" \
		--retry-delay "$CURL_RETRY_DELAY" \
		--retry-all-errors \
		-o "$output" \
		"$url"; then
		return 0
	fi

	echo "download_with_retry:: failed to download ${url} after ${CURL_MAX_RETRIES} attempts" >&2
	return 1
}

# Download and unpack GitHub tarball from main branch
#
# Outputs:
# - Writes extracted root path to stdout on success
#
# Returns:
# - 0 on success
# - 1 on failure
download_and_unpack() {
	local repo_url="${SEND_TO_SLACK_REPO_URL:-$DEFAULT_REPO_URL}"
	local tarball_url
	local temp_dir
	local tarball_file
	local extracted_root

	repo_url="${repo_url%.git}"
	tarball_url="${repo_url}/archive/${DEFAULT_REPO_BRANCH}.tar.gz"

	temp_dir=$(mktemp -d /tmp/install.XXXXXX)
	CLEANUP_ROOT="$temp_dir"
	tarball_file="${temp_dir}/source.tar.gz"

	if ! download_with_retry "$tarball_url" "$tarball_file"; then
		echo "download_and_unpack:: failed to download tarball" >&2
		return 1
	fi

	if ! require_commands tar; then
		echo "download_and_unpack:: tar command not found" >&2
		return 1
	fi

	if ! tar -xzf "$tarball_file" -C "$temp_dir"; then
		echo "download_and_unpack:: failed to extract tarball" >&2
		return 1
	fi

	# GitHub tarballs extract to a single directory named send-to-slack-<ref>
	# Find the extracted directory by looking for the expected files
	local dirs
	dirs=()
	while IFS= read -r dir; do
		if [[ -d "$dir" ]] && [[ -f "$dir/bin/send-to-slack.sh" ]] && [[ -d "$dir/lib" ]]; then
			dirs+=("$dir")
		fi
	done < <(find "$temp_dir" -maxdepth 1 -mindepth 1 -type d)

	if [[ ${#dirs[@]} -eq 0 ]]; then
		echo "download_and_unpack:: failed to locate extracted directory with expected files in ${temp_dir}" >&2
		return 1
	fi

	if [[ ${#dirs[@]} -gt 1 ]]; then
		echo "download_and_unpack:: found multiple extracted directories, expected exactly one" >&2
		return 1
	fi

	extracted_root="${dirs[0]}"

	echo "$extracted_root"
	return 0
}

# Validate installation prerequisites
#
# Inputs:
# - $1 - script_root: Root directory containing bin/send-to-slack.sh and lib/
#
# Returns:
# - 0 if all prerequisites are met
# - 1 if prerequisites are missing
validate_prerequisites() {
	local script_root="$1"

	if [[ ! -f "$script_root/bin/send-to-slack.sh" ]]; then
		echo "validate_prerequisites:: main script not found: ${script_root}/bin/send-to-slack.sh" >&2
		return 1
	fi

	if [[ ! -d "$script_root/lib" ]]; then
		echo "validate_prerequisites:: lib directory not found: ${script_root}/lib" >&2
		return 1
	fi

	return 0
}

# Perform the installation
#
# Inputs:
# - $1 - script_root: Root directory containing bin/send-to-slack.sh and lib/
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
	local install_root
	local manifest_dir
	local manifest_entries=()

	# Install supporting files to $prefix/lib/send-to-slack/ maintaining repo structure
	install_root="$prefix/lib/send-to-slack"
	manifest_dir=$(dirname "$manifest_file")
	install -d -m 755 "$install_root/bin/blocks"
	install -d -m 755 "$manifest_dir"
	install -d -m 755 "$prefix/bin"

	if [[ -L "$prefix/bin/send-to-slack" ]] || [[ -f "$prefix/bin/send-to-slack" ]]; then
		rm -f "$prefix/bin/send-to-slack"
	fi
	install -m 755 "$script_root/bin/send-to-slack.sh" "$prefix/bin/send-to-slack"
	manifest_entries+=("$prefix/bin/send-to-slack")

	# Install lib/ directory files (excluding blocks subdirectory)
	for file in "$script_root/lib"/*; do
		if [[ -f "$file" ]]; then
			install -m 755 "$file" "$install_root/bin/"
			manifest_entries+=("$install_root/bin/$(basename "$file")")
		fi
	done

	# Install lib/blocks/ directory files
	for file in "$script_root/lib/blocks"/*; do
		if [[ -f "$file" ]]; then
			install -m 755 "$file" "$install_root/bin/blocks/"
			manifest_entries+=("$install_root/bin/blocks/$(basename "$file")")
		fi
	done

	# Install VERSION file at root of install directory (matching repo structure)
	if [[ -f "${script_root}/${VERSION_FILE_NAME}" ]]; then
		install -m 644 "${script_root}/${VERSION_FILE_NAME}" "$install_root/${VERSION_FILE_NAME}"
		manifest_entries+=("$install_root/${VERSION_FILE_NAME}")
	fi

	printf '%s\n' "${manifest_entries[@]}" >"$manifest_file"

	return 0
}

# Perform installation from resolved script root
#
# Inputs:
# - $1 - script_root: Root directory containing bin/send-to-slack.sh and lib/
# - $2 - prefix: Installation prefix directory
#
# Returns:
# - 0 on success
# - 1 on failure
perform_installation() {
	local script_root="$1"
	local prefix="$2"
	local manifest_file

	if ! validate_prerequisites "$script_root"; then
		return 1
	fi

	manifest_file="$prefix/lib/send-to-slack/install_manifest.txt"

	if ! install_files "$script_root" "$prefix" "$manifest_file"; then
		return 1
	fi

	return 0
}

# Install from main branch
#
# Inputs:
# - $1 - prefix: Installation prefix directory
#
# Returns:
# - 0 on success
# - 1 on failure
install_latest_main() {
	local prefix="$1"
	local script_root

	if ! require_commands curl tar; then
		echo "install_latest_main:: required commands not found (curl, tar)" >&2
		return 1
	fi

	if ! script_root=$(download_and_unpack); then
		echo "install_latest_main:: failed to download and unpack from main branch" >&2
		return 1
	fi

	RESOLVED_REF="${DEFAULT_REPO_BRANCH}"

	if ! perform_installation "$script_root" "$prefix"; then
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
#
# Inputs:
# - CLI flags
#
# Returns:
# - 0 on success
# - 1 on failure
main() {
	local parse_result
	local install_prefix

	parse_result=0
	parse_args "$@" || parse_result=$?

	if [[ $parse_result -eq 2 ]]; then
		return 0
	fi

	if [[ $parse_result -ne 0 ]]; then
		usage
		abort "Invalid arguments. See usage above."
	fi

	# Determine install prefix based on whether running as root
	install_prefix=$(determine_install_prefix)

	if ! install_latest_main "$install_prefix"; then
		abort "Installation failed. See error messages above for details."
	fi

	echo "Installed send-to-slack to ${install_prefix}/bin/send-to-slack"
	echo "Supporting files installed to ${install_prefix}/lib/send-to-slack/"
	echo "Resolved reference: ${RESOLVED_REF}"

	return 0
}

# Only run main when script is executed directly, not when sourced
# This should safely allow piping and sourcing the script for unit testing while still working when piped
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]] || [[ -z "${BASH_SOURCE[0]:-}" ]]; then
	main "$@"
	exit $?
fi
