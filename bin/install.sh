#!/usr/bin/env bash
#
# Installation script for send-to-slack
# Installs send-to-slack from GitHub tarball
#
set -eo pipefail

# Configuration
VERSION_FILE_NAME="VERSION"
DEFAULT_REPO_URL="https://github.com/bluekornchips/send-to-slack"
DEFAULT_REPO_BRANCH="main"
CLEANUP_ROOT=""
RESOLVED_REF=""

# Network configuration
CURL_TIMEOUT=30
CURL_MAX_RETRIES=3
CURL_RETRY_DELAY=2

# Display usage information
#
# Side Effects:
# - Outputs usage message to stderr
#
# Returns:
# - 0 always
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
	return 0
}

# Cleanup temporary files on exit
#
# Side Effects:
# - Removes temporary directory if set
#
# Returns:
# - 0 always
cleanup() {
	if [[ -n "$CLEANUP_ROOT" && -d "$CLEANUP_ROOT" ]]; then
		rm -rf "$CLEANUP_ROOT"
	fi
	return 0
}

trap cleanup EXIT ERR

# Check if required commands are available
#
# Inputs:
# - $@ - commands to check
#
# Returns:
# - 0 if all commands are available
# - 1 if any command is missing
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

# Check if script is running as root
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

# Determine installation prefix based on user permissions
#
# Outputs:
# - Writes prefix path to stdout
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

# Download file with retry logic
#
# Inputs:
# - $1 - url: URL to download
# - $2 - output: Output file path
#
# Returns:
# - 0 on success
# - 1 on failure after retries
download_with_retry() {
	local url="$1"
	local output="$2"
	local attempt=1

	while [[ $attempt -le $CURL_MAX_RETRIES ]]; do
		if curl -fsSL \
			--connect-timeout "$CURL_TIMEOUT" \
			--max-time "$((CURL_TIMEOUT * 3))" \
			-o "$output" \
			"$url"; then
			return 0
		fi

		if [[ $attempt -lt $CURL_MAX_RETRIES ]]; then
			echo "download_with_retry:: attempt ${attempt} failed, retrying in ${CURL_RETRY_DELAY} seconds..." >&2
			sleep "$CURL_RETRY_DELAY"
		fi
		attempt=$((attempt + 1))
	done

	echo "download_with_retry:: failed to download ${url} after ${CURL_MAX_RETRIES} attempts" >&2
	return 1
}

# Download and unpack tarball from GitHub
#
# Outputs:
# - Writes extracted directory path to stdout on success
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

	echo "download_and_unpack:: downloading send-to-slack from ${tarball_url}"

	if ! download_with_retry "$tarball_url" "$tarball_file"; then
		echo "download_and_unpack:: failed to download tarball" >&2
		return 1
	fi

	if ! require_commands tar; then
		echo "download_and_unpack:: tar command not found" >&2
		return 1
	fi

	echo "download_and_unpack:: extracting archive"

	if ! tar -xzf "$tarball_file" -C "$temp_dir"; then
		echo "download_and_unpack:: failed to extract tarball" >&2
		return 1
	fi

	# Find the extracted directory
	local dirs
	dirs=()
	while IFS= read -r dir; do
		if [[ -d "$dir" ]] && [[ -f "$dir/send-to-slack.sh" ]] && [[ -d "$dir/lib" ]]; then
			dirs+=("$dir")
		fi
	done < <(find "$temp_dir" -maxdepth 1 -mindepth 1 -type d)

	if [[ ${#dirs[@]} -eq 0 ]]; then
		echo "download_and_unpack:: failed to locate extracted directory with expected files" >&2
		echo "download_and_unpack:: searched in: ${temp_dir}" >&2
		echo "download_and_unpack:: found directories:" >&2
		find "$temp_dir" -maxdepth 1 -mindepth 1 -type d -exec ls -la {} \; >&2 || true
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

# Validate that extracted archive contains required files
#
# Inputs:
# - $1 - script_root: Root directory of extracted archive
#
# Returns:
# - 0 if all required files are present
# - 1 if any required file is missing
validate_prerequisites() {
	local script_root="$1"

	if [[ ! -f "$script_root/send-to-slack.sh" ]]; then
		echo "validate_prerequisites:: send-to-slack.sh not found" >&2
		return 1
	fi

	if [[ ! -d "$script_root/lib" ]]; then
		echo "validate_prerequisites:: lib directory not found" >&2
		return 1
	fi

	return 0
}

# Install files to target prefix
#
# Inputs:
# - $1 - script_root: Root directory of extracted archive
# - $2 - prefix: Installation prefix directory
#
# Returns:
# - 0 on success
# - 1 on failure
install_files() {
	local script_root="$1"
	local prefix="$2"
	local install_dir="${prefix}/bin/send-to-slack"
	local lib_dir="${install_dir}/lib"

	echo "install_files:: installing to ${install_dir}"

	# Create installation directory
	if ! install -d -m 755 "$install_dir"; then
		echo "install_files:: failed to create installation directory: ${install_dir}" >&2
		return 1
	fi

	# Install executable
	if ! install -m 755 "$script_root/send-to-slack.sh" "$install_dir/send-to-slack"; then
		echo "install_files:: failed to install executable" >&2
		return 1
	fi

	# Install lib directory structure
	if ! install -d -m 755 "$lib_dir/blocks"; then
		echo "install_files:: failed to create lib directory: ${lib_dir}/blocks" >&2
		return 1
	fi

	# Install lib files
	for file in "$script_root/lib"/*; do
		if [[ -f "$file" ]]; then
			if ! install -m 755 "$file" "$lib_dir/"; then
				echo "install_files:: failed to install lib file: ${file}" >&2
				return 1
			fi
		fi
	done

	for file in "$script_root/lib/blocks"/*; do
		if [[ -f "$file" ]]; then
			if ! install -m 755 "$file" "$lib_dir/blocks/"; then
				echo "install_files:: failed to install block file: ${file}" >&2
				return 1
			fi
		fi
	done

	# Install VERSION file
	if [[ -f "${script_root}/${VERSION_FILE_NAME}" ]]; then
		if ! install -m 644 "${script_root}/${VERSION_FILE_NAME}" "$install_dir/${VERSION_FILE_NAME}"; then
			echo "install_files:: failed to install VERSION file" >&2
			return 1
		fi
	fi

	return 0
}

# Perform installation from local source directory
# This function is called when the script is sourced in Docker builds
#
# Inputs:
# - $1 - script_root: Root directory of source files
# - $2 - prefix: Installation prefix directory
#
# Returns:
# - 0 on success
# - 1 on failure
perform_installation() {
	local script_root="$1"
	local prefix="$2"

	if ! validate_prerequisites "$script_root"; then
		return 1
	fi

	if ! install_files "$script_root" "$prefix"; then
		return 1
	fi

	return 0
}

# Install latest version from main branch
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
		echo "install_latest_main:: failed to download and unpack" >&2
		return 1
	fi

	RESOLVED_REF="${DEFAULT_REPO_BRANCH}"

	if ! validate_prerequisites "$script_root"; then
		return 1
	fi

	if ! install_files "$script_root" "$prefix"; then
		return 1
	fi

	return 0
}

main() {
	local parse_result
	local install_prefix

	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-h | --help)
			usage
			return 0
			;;
		*)
			echo "install:: unknown option: $1" >&2
			usage
			return 1
			;;
		esac
		shift
	done

	install_prefix=$(determine_install_prefix)
	install_dir="${install_prefix}/bin/send-to-slack"

	echo "main:: this script will install:"
	echo "main::   ${install_dir}/send-to-slack"
	echo "main::   ${install_dir}/lib/"

	if ! install_latest_main "$install_prefix"; then
		echo "main:: installation failed. See error messages above for details." >&2
		return 1
	fi

	echo "main:: installed send-to-slack to ${install_dir}"
	echo "main:: executable available at ${install_dir}/send-to-slack"
	echo "main:: resolved reference: ${RESOLVED_REF}"

	if [[ ":${PATH}:" != *":${install_dir}:"* ]]; then
		echo "main:: ${install_dir} is not in your PATH." >&2
		echo "main:: add it to your PATH by running:"
		echo "main::   export PATH=\"${install_dir}:\$PATH\""
		echo
		echo "main:: to make this permanent, add the above line to your shell configuration file:"
		case "${SHELL}" in
		*/bash*)
			if [[ "$(uname)" == "Linux" ]]; then
				echo "main::   echo 'export PATH=\"${install_dir}:\$PATH\"' >> ~/.bashrc"
			else
				echo "main::   echo 'export PATH=\"${install_dir}:\$PATH\"' >> ~/.bash_profile"
			fi
			;;
		*/zsh*)
			echo "main::   echo 'export PATH=\"${install_dir}:\$PATH\"' >> ~/.zshrc"
			;;
		*)
			echo "main::   echo 'export PATH=\"${install_dir}:\$PATH\"' >> ~/.profile"
			;;
		esac
	fi

	return 0
}

# Only run main when script is executed directly, not when sourced
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]] || [[ -z "${BASH_SOURCE[0]:-}" ]]; then
	if ! main "$@"; then
		exit 1
	fi
	exit 0
fi
