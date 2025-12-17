#!/usr/bin/env bash
#
# Installation script for send-to-slack
# Installs send-to-slack from GitHub tarball
#
set -euo pipefail
IFS=$' \n\t'

# Fail fast with a concise message when not using bash
if [ -z "${BASH_VERSION:-}" ]; then
	echo "Bash is required to interpret this script." >&2
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

abort() {
	printf "%s\n" "$@" >&2
	exit 1
}

usage() {
	cat <<EOF >&2
usage: $0 [OPTIONS]

Install send-to-slack from GitHub tarball.
- Installs to ~/.local when run without sudo (default)
- Installs to /usr when run with sudo

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

cleanup() {
	if [[ -n "$CLEANUP_ROOT" && -d "$CLEANUP_ROOT" ]]; then
		rm -rf "$CLEANUP_ROOT"
	fi
	return 0
}

trap cleanup EXIT ERR

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

is_root() {
	if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
		return 0
	fi
	return 1
}

determine_install_prefix() {
	if is_root; then
		echo "/usr"
	else
		echo "${HOME}/.local"
	fi
}

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

install_files() {
	local script_root="$1"
	local prefix="$2"
	local bin_dir="${prefix}/bin"

	# Install executable directly to bin/
	install -d -m 755 "$bin_dir"
	install -m 755 "$script_root/send-to-slack.sh" "$bin_dir/send-to-slack"

	# Install lib files next to executable in bin/lib/
	install -d -m 755 "$bin_dir/lib/blocks"

	for file in "$script_root/lib"/*; do
		if [[ -f "$file" ]]; then
			install -m 755 "$file" "$bin_dir/lib/"
		fi
	done

	for file in "$script_root/lib/blocks"/*; do
		if [[ -f "$file" ]]; then
			install -m 755 "$file" "$bin_dir/lib/blocks/"
		fi
	done

	# Install VERSION file next to executable
	if [[ -f "${script_root}/${VERSION_FILE_NAME}" ]]; then
		install -m 644 "${script_root}/${VERSION_FILE_NAME}" "$bin_dir/${VERSION_FILE_NAME}"
	fi

	return 0
}

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

	install_prefix=$(determine_install_prefix)

	if ! install_latest_main "$install_prefix"; then
		abort "Installation failed. See error messages above for details."
	fi

	echo "Installed send-to-slack to ${install_prefix}/bin/"
	echo "Executable available at ${install_prefix}/bin/send-to-slack"
	echo "Resolved reference: ${RESOLVED_REF}"
	return 0
}

# Only run main when script is executed directly, not when sourced
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]] || [[ -z "${BASH_SOURCE[0]:-}" ]]; then
	main "$@"
	exit $?
fi
