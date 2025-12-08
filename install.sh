#!/usr/bin/env bash
#
# Installation script for send-to-slack
# Installs send-to-slack to the specified prefix directory
# Can be run locally from the repository or remotely via curl:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/bluekornchips/send-to-slack/main/install.sh)"
#
set -eo pipefail

########################################################
# Configuration
########################################################
REPO_URL="${INSTALL_REPO_URL:-https://github.com/bluekornchips/send-to-slack.git}"
REPO_BRANCH="${INSTALL_BRANCH:-main}"

# Display usage information
#
# Side Effects:
# - Outputs usage message to stderr
usage() {
	cat <<EOF >&2
usage: $0 [prefix]
  prefix: Installation prefix directory (default: ~/.local)
  e.g. $0 /usr/local
				$0 ~/.local
				$0
EOF
}

# Check if a command exists
command_exists() {
	command -v "$1" >/dev/null 2>&1
}

# Check bash version (requires 4.0+)
check_bash_version() {
	local bash_version
	bash_version=$(bash --version | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -n1)
	local major_version
	major_version=$(echo "$bash_version" | cut -d. -f1)
	local minor_version
	minor_version=$(echo "$bash_version" | cut -d. -f2)

	if [[ -z "$major_version" ]] || [[ -z "$minor_version" ]]; then
		echo "check_bash_version:: Unable to determine bash version" >&2
		return 1
	fi

	if [[ $major_version -lt 4 ]] || ([[ $major_version -eq 4 ]] && [[ $minor_version -lt 0 ]]); then
		echo "check_bash_version:: Bash 4.0 or later is required (found: $bash_version)" >&2
		return 1
	fi

	return 0
}

# Check runtime dependencies (jq, curl)
check_runtime_dependencies() {
	local missing_deps=()

	if ! command_exists jq; then
		missing_deps+=("jq")
	fi

	if ! command_exists curl; then
		missing_deps+=("curl")
	fi

	if [[ ${#missing_deps[@]} -gt 0 ]]; then
		echo "check_runtime_dependencies:: Missing required runtime dependencies: ${missing_deps[*]}" >&2
		echo "check_runtime_dependencies:: These are required for send-to-slack to function" >&2
		echo "check_runtime_dependencies:: Please install: ${missing_deps[*]}" >&2
		return 1
	fi

	return 0
}

# Check installation dependencies (git for remote install)
check_install_dependencies() {
	if ! command_exists git; then
		echo "check_install_dependencies:: git is required for remote installation" >&2
		echo "check_install_dependencies:: Please install git: https://git-scm.com/downloads" >&2
		return 1
	fi

	return 0
}

# Clone repository to temporary directory if running remotely
#
# Returns:
# - Outputs path to cloned repository on success
# - Returns 1 on failure
clone_repository_if_needed() {
	local script_root="$1"
	local temp_dir

	# Check if we're in a valid repository directory
	if [[ -f "$script_root/send-to-slack.sh" ]] && [[ -d "$script_root/bin" ]]; then
		# We're already in the repository, return the current directory
		echo "$script_root"
		return 0
	fi

	# We're not in the repository, need to clone it
	if ! check_install_dependencies; then
		return 1
	fi

	temp_dir=$(mktemp -d)
	trap 'rm -rf "$temp_dir"' EXIT

	echo "clone_repository_if_needed:: Cloning repository from ${REPO_URL} (branch: ${REPO_BRANCH})..." >&2

	if ! git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$temp_dir" 2>&1; then
		echo "clone_repository_if_needed:: Failed to clone repository" >&2
		rm -rf "$temp_dir"
		return 1
	fi

	echo "$temp_dir"
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
		echo "validate_prerequisites: main script not found: $script_root/send-to-slack.sh" >&2
		return 1
	fi

	if [[ ! -d "$script_root/bin" ]]; then
		echo "validate_prerequisites: bin directory not found: $script_root/bin" >&2
		return 1
	fi

	return 0
}

# Perform the installation
#
# Inputs:
# - $1 - script_root: Root directory containing send-to-slack.sh and bin/
# - $2 - prefix: Installation prefix directory
#
# Returns:
# - 0 on success
# - 1 on failure
install_files() {
	local script_root="$1"
	local prefix="$2"

	install -d -m 755 "$prefix/bin/blocks"
	install -m 755 "$script_root/send-to-slack.sh" "$prefix/bin/send-to-slack"

	for file in "$script_root/bin"/*; do
		if [[ -f "$file" ]]; then
			install -m 755 "$file" "$prefix/bin/"
		fi
	done

	for file in "$script_root/bin/blocks"/*; do
		if [[ -f "$file" ]]; then
			install -m 755 "$file" "$prefix/bin/blocks/"
		fi
	done

	return 0
}

# Main entry point
#
# Inputs:
# - $1 - prefix: Installation prefix directory (optional, defaults to ~/.local)
#
# Returns:
# - 0 on success
# - 1 on failure
main() {
	local script_root
	local prefix
	local default_prefix
	local temp_repo
	local needs_cleanup=false

	# Check bash version first
	if ! check_bash_version; then
		return 1
	fi

	# Check runtime dependencies (needed for send-to-slack to work)
	if ! check_runtime_dependencies; then
		return 1
	fi

	# Determine script location
	# When run via curl, $0 might be "bash" or empty, so we need to detect that
	script_root="${0%/*}"
	# Handle case where script is run via curl (script_root might be empty, ".", or "/")
	# Also check if the script_root actually contains our files
	if [[ -z "$script_root" ]] || [[ "$script_root" == "/" ]] || [[ "$script_root" == "." ]] || [[ ! -f "$script_root/send-to-slack.sh" ]]; then
		# We're likely running remotely, will clone repo below
		script_root="."
	fi

	default_prefix="${HOME}/.local"
	prefix="${1%/}"

	# Use default prefix if none provided
	if [[ -z "$prefix" ]]; then
		if [[ -z "$HOME" ]]; then
			echo "main:: HOME environment variable is not set and no prefix provided" >&2
			usage
			return 1
		fi
		prefix="$default_prefix"
	fi

	# Expand ~ to home directory if present
	if [[ "$prefix" == ~* ]] && [[ -n "$HOME" ]]; then
		prefix="${prefix/#\~/$HOME}"
	fi

	# Check if we need to clone the repository (running remotely)
	if ! temp_repo=$(clone_repository_if_needed "$script_root"); then
		return 1
	fi

	# Set cleanup trap if we cloned to a temp directory
	if [[ "$temp_repo" != "$script_root" ]]; then
		needs_cleanup=true
		trap 'rm -rf "$temp_repo"' EXIT
		script_root="$temp_repo"
	fi

	# Validate that we have the required files
	if ! validate_prerequisites "$script_root"; then
		return 1
	fi

	# Perform installation
	if ! install_files "$script_root" "$prefix"; then
		return 1
	fi

	echo "main:: Installed send-to-slack to ${prefix}/bin/send-to-slack"

	# Cleanup if we cloned to a temp directory
	if [[ "$needs_cleanup" == "true" ]]; then
		rm -rf "$temp_repo"
		trap - EXIT
	fi

	return 0
}

# Only run main when script is executed directly, not when sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
	exit $?
fi
