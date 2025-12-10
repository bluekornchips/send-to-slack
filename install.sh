#!/usr/bin/env bash
#
# Installation script for send-to-slack
# Installs send-to-slack to the specified prefix directory
#
set -eo pipefail

VERSION_FILE_NAME="VERSION"
DEFAULT_INSTALL_PATH="${HOME:+${HOME}/.local}"
FALLBACK_INSTALL_PATH="/usr/local"
DEFAULT_REPO_URL="https://github.com/bluekornchips/send-to-slack.git"
CLEANUP_ROOT=""

# Display usage information
#
# Side Effects:
# - Outputs usage message to stderr
usage() {
	cat <<EOF >&2
usage: $0 [--commit <sha>] [--path <prefix>]
  --commit <sha>  Install from a specific commit (cloned fresh)
  --path <prefix> Installation prefix (default: ~/.local or /usr/local)
  -h, --help      Show this help message
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

# Clone a specific commit into a temporary directory
#
# Inputs:
# - $1 - commit_ref: Commit SHA to checkout
# - $2 - repo_url: Repository URL to clone from
#
# Outputs:
# - Writes cloned root path to stdout on success
#
# Returns:
# - 0 on success
# - 1 on failure
clone_commit_to_temp() {
	local commit_ref="$1"
	local repo_url="$2"
	local temp_root
	local clone_root

	if [[ -z "$commit_ref" ]]; then
		echo "clone_commit_to_temp:: commit_ref is required" >&2
		return 1
	fi

	if [[ -z "$repo_url" ]]; then
		echo "clone_commit_to_temp:: repo_url is required" >&2
		return 1
	fi

	if ! require_commands git; then
		return 1
	fi

	temp_root=$(mktemp -d /tmp/send-to-slack-install.XXXXXX)
	clone_root="${temp_root}/repo"
	CLEANUP_ROOT="$temp_root"

	if [[ -z "$temp_root" || ! -d "$temp_root" ]]; then
		echo "clone_commit_to_temp:: failed to create temp directory" >&2
		return 1
	fi

	if ! git clone "$repo_url" "$clone_root" >/dev/null 2>&1; then
		echo "clone_commit_to_temp:: git clone failed for ${repo_url}" >&2
		return 1
	fi

	if ! (cd "$clone_root" && git checkout "$commit_ref" >/dev/null 2>&1); then
		echo "clone_commit_to_temp:: failed to checkout commit ${commit_ref}" >&2
		return 1
	fi

	echo "$clone_root"

	return 0
}

# Resolve version string from a repo at a specific commit
#
# Inputs:
# - $1 - commit_ref: Commit SHA to read
# - $2 - repo_root: Local repository path
#
# Outputs:
# - Writes version string to stdout on success
#
# Returns:
# - 0 on success
# - 1 on failure
get_version_from_commit() {
	local commit_ref="$1"
	local repo_root="$2"
	local version_value

	if [[ -z "$commit_ref" || -z "$repo_root" ]]; then
		return 1
	fi

	if ! command -v git >/dev/null 2>&1; then
		return 1
	fi

	if version_value=$(git -C "$repo_root" show "${commit_ref}:VERSION" 2>/dev/null); then
		version_value=$(echo "$version_value" | tr -d '\r' | tr -d '\n')
		if [[ -n "$version_value" ]]; then
			echo "$version_value"
			return 0
		fi
	fi

	return 1
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
	local prefix
	local default_prefix
	local manifest_file
	local commit_ref
	local repo_url
	local resolved_version

	default_prefix="$DEFAULT_INSTALL_PATH"

	if [[ -z "$default_prefix" ]]; then
		default_prefix="$FALLBACK_INSTALL_PATH"
	fi

	prefix=""
	manifest_file=""
	commit_ref=""
	repo_url="${SEND_TO_SLACK_REPO_URL:-$DEFAULT_REPO_URL}"
	resolved_version=""
	script_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--commit)
			if [[ $# -lt 2 ]]; then
				echo "main:: --commit requires a value" >&2
				usage
				return 1
			fi
			commit_ref="$2"
			shift 2
			;;
		--path)
			if [[ $# -lt 2 ]]; then
				echo "main:: --path requires a value" >&2
				usage
				return 1
			fi
			prefix="${2%/}"
			shift 2
			;;
		-h | --help)
			usage
			return 0
			;;
		-*)
			echo "main:: unknown option: $1" >&2
			usage
			return 1
			;;
		*)
			if [[ -n "$prefix" ]]; then
				echo "main:: install path already specified: ${prefix}" >&2
				usage
				return 1
			fi
			prefix="${1%/}"
			shift
			;;
		esac
	done

	if [[ -z "$prefix" ]]; then
		prefix="$default_prefix"
	fi

	if [[ "$prefix" == ~* ]] && [[ -n "$HOME" ]]; then
		prefix="${prefix/#\~/$HOME}"
	fi

	if [[ -n "$commit_ref" ]]; then
		if ! script_root=$(clone_commit_to_temp "$commit_ref" "$repo_url"); then
			return 1
		fi

		if resolved_version=$(get_version_from_commit "$commit_ref" "$script_root"); then
			resolved_version="$resolved_version"
		else
			resolved_version="$commit_ref"
		fi
	fi

	if ! validate_prerequisites "$script_root"; then
		return 1
	fi

	manifest_file="$prefix/share/send-to-slack/install_manifest.txt"

	if ! install_files "$script_root" "$prefix" "$manifest_file"; then
		return 1
	fi

	if [[ -n "$commit_ref" ]]; then
		if [[ -z "$resolved_version" && -f "${script_root}/${VERSION_FILE_NAME}" ]]; then
			resolved_version=$(tr -d '\r' <"${script_root}/${VERSION_FILE_NAME}" | tr -d '\n')
		fi

		if [[ -z "$resolved_version" ]]; then
			resolved_version="$commit_ref"
		fi

		mkdir -p "$prefix/share/send-to-slack"
		printf '%s\n' "$resolved_version" >"$prefix/share/send-to-slack/${VERSION_FILE_NAME}"
	fi

	echo "main:: Installed send-to-slack to ${prefix}/bin/send-to-slack"

	return 0
}

# Only run main when script is executed directly, not when sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
	exit $?
fi
