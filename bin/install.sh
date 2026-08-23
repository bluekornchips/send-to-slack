#!/usr/bin/env bash
#
# Install helper for send-to-slack
#

# Detect if script is being piped (BASH_SOURCE[0] will be /dev/stdin or similar)
if [[ "${BASH_SOURCE[0]}" == "/dev/stdin" ]] \
	|| [[ "${BASH_SOURCE[0]}" == "-" ]] \
	|| [[ ! -f "${BASH_SOURCE[0]}" ]]; then
	SCRIPT_DIR=""
	IS_PIPED=1
else
	SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	IS_PIPED=0
fi
UPSTREAM_REPO="bluekornchips/send-to-slack"
DEFAULT_PREFIX="${HOME}/.local/bin"
# Default to /usr/local/bin for root so the binary lands on PATH in containers.
if [[ "$(id -u)" -eq 0 ]]; then
	DEFAULT_PREFIX="/usr/local/bin"
fi
INSTALL_BASENAME="send-to-slack"
INSTALL_SIGNATURE="# send-to-slack install signature: v1"
GITHUB_REPO="${GITHUB_REPO:-${UPSTREAM_REPO}}"
REPO_URL="${REPO_URL:-https://github.com/${GITHUB_REPO}.git}"
# Set only during remote install so EXIT trap can remove the directory after
# main returns
_INSTALL_TMPDIR=""

# Remove long-lived temp directory created for clone or archive install
#
# Side Effects:
# - Removes directory at _INSTALL_TMPDIR when set and present
#
# Returns:
# - 0 always
cleanup_install_tmpdir() {
	if [[ -n "${_INSTALL_TMPDIR}" ]] && [[ -d "${_INSTALL_TMPDIR}" ]]; then
		rm -rf "${_INSTALL_TMPDIR}"
	fi

	return 0
}

# Display usage information
#
# Side Effects:
# - Outputs usage details to stdout
#
# Returns:
# - 0 always
usage() {
	cat <<EOF
Usage: $(basename "$0") [--prefix <dir>] [--force] [--version <tag>|local]
[--help]

Options:
--prefix <dir> Target directory for installation (default: ${DEFAULT_PREFIX})
  --force          Overwrite existing file even if unsigned
--version <tag> Install from specific branch/tag (default: main). Use "local" to
install from the current repo.
  -h, --help       Show this help message

Behavior:
- Installs lib/, bin helpers, and send-to-slack under a fixed install root, then
symlinks the prefix to that tree
  - With --version local, installs from the repository containing this script
  - Appends a signature comment for safe uninstall validation
  - Refuses system prefixes like /usr or /etc; choose a writable user path
  - Creates the prefix if missing and sets mode 0755 on the installed script
EOF
	return 0
}

# Validate that at least one tool is available
#
# Returns:
# - 0 on success, 1 if no tools available
check_dependencies() {
	# Git takes priority, archive path needs curl and tar
	if command -v "git" >/dev/null 2>&1; then
		return 0
	fi

	if command -v "curl" >/dev/null 2>&1 && command -v "tar" >/dev/null 2>&1; then
		return 0
	fi

	echo "check_dependencies:: missing required commands: need 'git'," \
		"or 'curl' and 'tar'" >&2
	return 1
}

# Normalize prefix and preserve root
#
# Inputs:
# - $1 - path to normalize
# Outputs:
# - Writes normalized path to stdout
# Returns:
# - 0 on success, 1 on empty input
normalize_prefix() {
	local path="$1"

	if [[ -z "$path" ]]; then
		echo "normalize_prefix:: prefix is empty" >&2
		return 1
	fi

	if [[ "$path" == "/" ]]; then
		echo "/"
		return 0
	fi

	echo "${path%/}"
	return 0
}

# Check if prefix is allowed and writable; create if missing
#
# Inputs:
# - $1 - target prefix
# Returns:
# - 0 on success, 1 on failure
ensure_prefix() {
	local prefix="$1"

	if [[ -z "$prefix" ]]; then
		echo "ensure_prefix:: prefix is empty" >&2
		return 1
	fi

	case "$prefix" in
		/usr/local/*) ;;
		/usr/* | /etc/*)
			echo "ensure_prefix:: refusing system prefix: $prefix" >&2
			return 1
			;;
	esac

	if [[ ! -d "$prefix" ]]; then
		if ! mkdir -p "$prefix"; then
			echo "ensure_prefix:: cannot create prefix: $prefix" >&2
			return 1
		fi
	fi

	if [[ ! -w "$prefix" ]]; then
		echo "ensure_prefix:: prefix not writable: $prefix" >&2
		return 1
	fi

	return 0
}

# Check for install signature on an existing file
#
# Inputs:
# - $1 - file path
# Returns:
# - 0 when signature is present, 1 otherwise
file_has_signature() {
	local path="$1"

	if [[ ! -f "$path" ]]; then
		return 1
	fi

	if grep -Fq "$INSTALL_SIGNATURE" "$path"; then
		return 0
	fi

	return 1
}

# Resolve the fixed install root for a prefix
#
# Inputs:
# - $1 - normalized prefix
# Outputs:
# - Writes install root path to stdout
_resolve_install_root() {
	local normalized_prefix="$1"

	if [[ "$(id -u)" -eq 0 ]] || [[ "$normalized_prefix" == /usr/local/* ]] \
		|| [[ "$normalized_prefix" == /usr/* ]]; then
		echo "/usr/local/send-to-slack"
	else
		echo "${HOME}/.local/share/send-to-slack"
	fi

	return 0
}

# Validate a staged install tree against the explicit library manifest
#
# Inputs:
# - $1 - install root containing send-to-slack and lib/
# Returns:
# - 0 when the tree is complete
# - 1 when required files are missing
_validate_install_tree() {
	local install_tree="$1"
	local loader_file
	local rel
	local abs

	if [[ -z "$install_tree" || ! -d "$install_tree" ]]; then
		echo "_validate_install_tree:: install tree not found: ${install_tree}" >&2
		return 1
	fi

	if [[ ! -f "${install_tree}/send-to-slack" ]]; then
		echo "_validate_install_tree:: missing send-to-slack binary" >&2
		return 1
	fi

	loader_file="${install_tree}/lib/loader.sh"
	if [[ ! -f "$loader_file" ]]; then
		echo "_validate_install_tree:: missing lib/loader.sh" >&2
		return 1
	fi

	# shellcheck source=lib/loader.sh disable=SC1090,SC1091
	source "$loader_file"

	for rel in "${SEND_TO_SLACK_LIB_MANIFEST[@]}"; do
		abs="${install_tree}/lib/${rel}"
		if [[ ! -f "$abs" ]]; then
			echo "_validate_install_tree:: missing manifest module: lib/${rel}" >&2
			return 1
		fi
	done

	if [[ ! -d "${install_tree}/lib/slack/block-kit/blocks" ]]; then
		echo "_validate_install_tree:: missing lib/slack/block-kit/blocks" \
			"directory" >&2
		return 1
	fi

	return 0
}

# Copy source into a fresh staging directory and validate it
#
# Inputs:
# - $1 - source directory path
# - $2 - staging directory path
# Returns:
# - 0 on success
# - 1 on failure
_assemble_install_staging() {
	local source_dir="$1"
	local staging_dir="$2"

	if [[ -z "$source_dir" || ! -d "$source_dir" ]]; then
		echo "_assemble_install_staging:: source directory not found:" \
			"${source_dir}" >&2
		return 1
	fi

	if [[ -z "$staging_dir" ]]; then
		echo "_assemble_install_staging:: staging directory is empty" >&2
		return 1
	fi

	if ! mkdir -p "${staging_dir}/lib"; then
		echo "_assemble_install_staging:: failed to create staging lib directory" >&2
		return 1
	fi

	if ! cp "${source_dir}/bin/send-to-slack.sh" \
		"${staging_dir}/send-to-slack"; then
		echo "_assemble_install_staging:: failed to copy send-to-slack.sh" >&2
		return 1
	fi

	if ! chmod 0755 "${staging_dir}/send-to-slack"; then
		echo "_assemble_install_staging:: failed to chmod staged binary" >&2
		return 1
	fi

	if ! cp -a "${source_dir}/lib/." "${staging_dir}/lib/"; then
		echo "_assemble_install_staging:: failed to copy lib tree" >&2
		return 1
	fi

	if [[ -f "${source_dir}/VERSION" ]]; then
		if ! cp "${source_dir}/VERSION" "${staging_dir}/VERSION"; then
			echo "_assemble_install_staging:: failed to copy VERSION" >&2
			return 1
		fi
	fi

	if ! _validate_install_tree "$staging_dir"; then
		return 1
	fi

	if ! printf '\n%s\n' "$INSTALL_SIGNATURE" \
		>>"${staging_dir}/send-to-slack"; then
		echo "_assemble_install_staging:: failed to append signature" >&2
		return 1
	fi

	if ! file_has_signature "${staging_dir}/send-to-slack"; then
		echo "_assemble_install_staging:: signature verification failed" >&2
		return 1
	fi

	return 0
}

# List lib/*.sh to install, relative to root_dir.
_install_lib_rel_paths() {
	local root_dir="$1"
	local abs

	find "${root_dir}/lib" \
		-mindepth 1 \
		-type f \
		-name '*.sh' \
		| LC_ALL=C sort | while IFS= read -r abs; do
		printf '%s\n' "${abs#"${root_dir}/"}"
	done
}

# Install from extracted source directory
# Inputs:
# - $1 - source directory path
# - $2 - prefix
# - $3 - force flag, 1 enables overwrite without signature
install_from_source() {
	local source_dir="$1"
	local prefix="$2"
	local force="${3:-0}"
	local normalized_prefix
	local install_root
	local target_binary
	local staging_dir
	local previous_backup=""

	if [[ -z "$source_dir" ]] || [[ ! -d "$source_dir" ]]; then
		echo "install_from_source:: source directory not found: $source_dir" >&2
		return 1
	fi

	if ! normalized_prefix=$(normalize_prefix "$prefix"); then
		return 1
	fi

	if [[ ! -f "${source_dir}/bin/send-to-slack.sh" ]]; then
		echo "install_from_source:: missing bin/send-to-slack.sh" >&2
		return 1
	fi

	if [[ ! -d "${source_dir}/lib" ]]; then
		echo "install_from_source:: missing lib directory" >&2
		return 1
	fi

	install_root="$(_resolve_install_root "$normalized_prefix")"
	target_binary="${normalized_prefix}/${INSTALL_BASENAME}"

	if [[ -f "$target_binary" ]] && ((force != 1)); then
		if ! file_has_signature "$target_binary"; then
			echo "install_from_source:: existing file lacks signature, use --force to" \
				"overwrite: $target_binary" >&2
			return 1
		fi
	fi

	staging_dir=$(mktemp -d \
		"${TMPDIR:-/tmp}/send-to-slack-install-staging.XXXXXX") || {
		echo "install_from_source:: mktemp failed for staging directory" >&2
		return 1
	}

	if ! _assemble_install_staging "$source_dir" "$staging_dir"; then
		rm -rf "$staging_dir"
		return 1
	fi

	if ! install -d -m 755 "$(dirname "$target_binary")"; then
		echo "install_from_source:: failed to create prefix directory" >&2
		rm -rf "$staging_dir"
		return 1
	fi

	if ! install -d -m 755 "$(dirname "$install_root")"; then
		echo "install_from_source:: failed to create install root parent" \
			"directory" >&2
		rm -rf "$staging_dir"
		return 1
	fi

	if [[ -d "$install_root" ]]; then
		previous_backup=$(mktemp -d \
			"${TMPDIR:-/tmp}/send-to-slack-install-backup.XXXXXX") || {
			echo "install_from_source:: mktemp failed for backup directory" >&2
			rm -rf "$staging_dir"
			return 1
		}
		if ! mv "$install_root" "${previous_backup}/previous"; then
			echo "install_from_source:: failed to move existing install tree aside" >&2
			rm -rf "$staging_dir" "$previous_backup"
			return 1
		fi
	fi

	if ! mv "$staging_dir" "$install_root"; then
		echo "install_from_source:: failed to activate staged install tree" >&2
		if [[ -n "$previous_backup" && -d "${previous_backup}/previous" ]]; then
			mv "${previous_backup}/previous" "$install_root" 2>/dev/null || true
		fi
		rm -rf "$staging_dir" "$previous_backup"
		return 1
	fi

	rm -rf "$previous_backup"

	if [[ -L "$target_binary" ]] || [[ -f "$target_binary" ]]; then
		rm -f "$target_binary"
	fi

	if ! ln -sf "${install_root}/send-to-slack" "$target_binary"; then
		echo "install_from_source:: failed to create symlink" >&2
		return 1
	fi

	echo "install_from_source:: installed $target_binary"
	return 0
}

# Verify installation by checking if command is available
#
# Inputs:
# - $1 - prefix
# Returns:
# - 0 if command is found, 1 if not found
verify_installation() {
	local prefix="$1"
	local normalized_prefix
	local target_path

	if ! normalized_prefix=$(normalize_prefix "$prefix"); then
		return 1
	fi

	target_path="${normalized_prefix}/${INSTALL_BASENAME}"

	# Check if the installed binary exists and is executable, or if command is
	# available in a subshell
	if [[ -x "$target_path" ]] \
		|| (command -v "$INSTALL_BASENAME" >/dev/null 2>&1); then
		return 0
	fi

	return 1
}

# Provide post-install guidance
# Inputs:
# - $1 - prefix
# Returns:
# - 0 always
print_next_steps() {
	local prefix="$1"
	local normalized_prefix

	if ! normalized_prefix=$(normalize_prefix "$prefix"); then
		return 0
	fi

	if [[ ":${PATH}:" != *":${normalized_prefix}:"* ]]; then
		echo "print_next_steps:: add to PATH: export" \
			"PATH=\"${normalized_prefix}:\$PATH\""
	fi

	echo "print_next_steps:: installed binary:" \
		"${normalized_prefix}/${INSTALL_BASENAME}"
	return 0
}

# Print install metadata from a cloned or extracted source directory
#
# Inputs:
# - $1 - source directory path, may be a git repo or plain directory
# - $2 - git ref used for the install, branch or tag
# Returns:
# - 0 always
print_install_info() {
	local source_dir="$1"
	local git_ref="$2"
	local commit
	local describe

	if [[ -z "$source_dir" ]] || [[ ! -d "$source_dir" ]]; then
		return 0
	fi

	if command -v "git" >/dev/null 2>&1 && [[ -d "${source_dir}/.git" ]]; then
		commit=$(git -C "$source_dir" rev-parse HEAD 2>/dev/null || echo "unknown")
		describe=$(git -C "$source_dir" describe --tags --always \
			echo "$git_ref" 2>/dev/null)
	else
		commit="unknown"
		describe="$git_ref"
	fi

	cat <<EOF
install:: ref:     $git_ref
install:: version: $describe
install:: commit:  $commit
EOF

	return 0
}

# Clone repository using git
#
# Inputs:
# - $1 - git reference, branch/tag
# - $2 - output directory
# - REPO_URL, git remote URL, defaults to https://github.com/${GITHUB_REPO}.git
# Outputs:
# - Sets CLONE_DIR global variable to the cloned directory
# Returns:
# - 0 on success, 1 on failure
clone_repository() {
	local ref="$1"
	local output_dir="$2"
	local clone_output
	local temp_clone_dir

	if [[ -z "$ref" ]]; then
		echo "clone_repository:: ref is empty" >&2
		return 1
	fi

	if [[ -z "$output_dir" ]] || [[ ! -d "$output_dir" ]]; then
		echo "clone_repository:: output directory not found: $output_dir" >&2
		return 1
	fi

	if ! command -v "git" >/dev/null 2>&1; then
		echo "clone_repository:: git command not available" >&2
		return 1
	fi

	if [[ -z "$REPO_URL" ]]; then
		echo "clone_repository:: REPO_URL is empty" >&2
		return 1
	fi

	temp_clone_dir=$(mktemp -d "${output_dir}/send-to-slack.XXXXXX") || {
		echo "clone_repository:: mktemp failed under ${output_dir}" >&2
		return 1
	}

	# Try cloning with the ref as branch/tag
	if ! clone_output=$(git clone --depth 1 --branch "$ref" "$REPO_URL" \
		"$temp_clone_dir" 2>&1); then
		# Destination may already exist after a failed clone; recreate before retry.
		rm -rf "$temp_clone_dir"
		temp_clone_dir=$(mktemp -d "${output_dir}/send-to-slack.XXXXXX") || {
			echo "clone_repository:: mktemp failed under ${output_dir}" >&2
			return 1
		}

		if ! clone_output=$(git clone --depth 1 "$REPO_URL" \
			"$temp_clone_dir" 2>&1); then
			echo "clone_repository:: failed to clone repository: $clone_output" >&2
			rm -rf "$temp_clone_dir"
			return 1
		fi
		if ! clone_output=$(git -C "$temp_clone_dir" checkout "$ref" 2>&1); then
			echo "clone_repository:: failed to checkout ref $ref: $clone_output" >&2
			rm -rf "$temp_clone_dir"
			return 1
		fi
	fi

	CLONE_DIR="$temp_clone_dir"
	return 0
}

# Build source archive URL for a branch/tag
# GitHub provides tar.gz format
#
# Inputs:
# - $1 - git reference, branch/tag
# Outputs:
# - Sets ARTIFACT_URL and ARTIFACT_EXT global variables
# Returns:
# - 0 on success, 1 on failure
build_source_archive_url() {
	local ref="$1"
	local base_url
	local ref_type="heads"

	if [[ -z "$ref" ]]; then
		echo "build_source_archive_url:: ref is empty" >&2
		return 1
	fi

	# If ref looks like a tag (starts with v), use tags instead of heads
	if [[ "$ref" =~ ^v[0-9] ]]; then
		ref_type="tags"
	fi

	# Build URL for tar.gz format
	base_url="https://github.com/${GITHUB_REPO}/archive/refs/${ref_type}/""\
${ref}.tar.gz"
	ARTIFACT_EXT=".tar.gz"

	ARTIFACT_URL="$base_url"
	return 0
}

# Download file
download_file() {
	local url="$1"
	local output="$2"

	if ! curl --proto "=https" --tlsv1.2 --fail --show-error --location --output \
		"$output" "$url"; then
		echo "download_file:: failed to download $url" >&2
		return 1
	fi

	return 0
}

# Extract archive based on file extension
# Supports: tar.gz
# Uses: tar
#
# Inputs:
# - $1 - archive file path
# - $2 - output directory
# Returns:
# - 0 on success, 1 on failure
extract_archive() {
	local archive_path="$1"
	local output_dir="$2"

	if [[ -z "$archive_path" ]] || [[ ! -f "$archive_path" ]]; then
		echo "extract_archive:: archive file not found: $archive_path" >&2
		return 1
	fi

	if [[ -z "$output_dir" ]] || [[ ! -d "$output_dir" ]]; then
		echo "extract_archive:: output directory not found: $output_dir" >&2
		return 1
	fi

	if [[ "$archive_path" == *.tar.gz ]]; then
		if ! command -v "tar" >/dev/null 2>&1; then
			echo "extract_archive:: tar command not available" >&2
			return 1
		fi
		if ! tar -xzf "$archive_path" -C "$output_dir"; then
			echo "extract_archive:: failed to extract tar.gz archive" >&2
			return 1
		fi
	else
		echo "extract_archive:: unsupported archive format: $archive_path" >&2
		return 1
	fi

	return 0
}

main() {
	local prefix
	local force
	local version
	local artifact_url
	local artifact_ext
	local archive_path
	local extract_dir
	local source_dir
	local cand

	prefix="$DEFAULT_PREFIX"
	force=0
	version=""
	artifact_url=""
	artifact_ext=""

	while [[ $# -gt 0 ]]; do
		case "$1" in
			--prefix)
				shift
				if [[ -z "${1:-}" ]]; then
					echo "main:: --prefix requires a value" >&2
					return 1
				fi
				prefix="$1"
				;;
			--prefix=*)
				prefix="${1#*=}"
				;;
			--force)
				force=1
				;;
			--version)
				shift
				if [[ -z "${1:-}" ]]; then
					echo "main:: --version requires a value" >&2
					return 1
				fi
				version="$1"
				;;
			-h | --help)
				usage
				return 0
				;;
			*)
				echo "main:: unknown option: $1" >&2
				return 1
				;;
		esac
		shift
	done

	if [[ "$version" == "local" ]]; then
		if [[ "$IS_PIPED" -eq 1 ]]; then
			echo "main:: --version local not supported when script is piped," \
				"downloading from GitHub instead" >&2
			version=""
		else
			if ! check_dependencies; then
				return 1
			fi
			if ! ensure_prefix "$prefix"; then
				return 1
			fi
			if ! install_from_source "${SCRIPT_DIR}/.." "$prefix" "$force"; then
				return 1
			fi
			print_next_steps "$prefix"
			if ! verify_installation "$prefix"; then
				echo "main:: installation verification failed: command not found" >&2
				return 1
			fi
			return 0
		fi
	fi

	if ! check_dependencies; then
		return 1
	fi

	local git_ref="${version:-main}"

	if ! ensure_prefix "$prefix"; then
		return 1
	fi

	_INSTALL_TMPDIR=$(mktemp -d)
	trap cleanup_install_tmpdir EXIT

	# Try git clone first if git is available, otherwise use archive downloads
	if command -v "git" >/dev/null 2>&1; then
		if ! clone_repository "$git_ref" "$_INSTALL_TMPDIR"; then
			echo "main:: failed to clone repository, falling back to archive" \
				"download" >&2
			# Fall through to archive download
		else
			source_dir="$CLONE_DIR"
			if [[ -z "$source_dir" ]] || [[ ! -d "$source_dir" ]]; then
				echo "main:: failed to find cloned source directory" >&2
				return 1
			fi

			print_install_info "$source_dir" "$git_ref"

			if ! install_from_source "$source_dir" "$prefix" "$force"; then
				return 1
			fi

			print_next_steps "$prefix"
			if ! verify_installation "$prefix"; then
				echo "main:: installation verification failed: command not found" >&2
				return 1
			fi
			return 0
		fi
	fi

	# Fallback to archive download
	build_source_archive_url "$git_ref"
	artifact_url="$ARTIFACT_URL"
	artifact_ext="$ARTIFACT_EXT"
	archive_path="${_INSTALL_TMPDIR}/source${artifact_ext}"

	if ! download_file "$artifact_url" "$archive_path"; then
		echo "main:: failed to download source archive" >&2
		return 1
	fi

	extract_dir="${_INSTALL_TMPDIR}/extract"
	if ! mkdir -p "$extract_dir"; then
		echo "main:: failed to create extract directory" >&2
		return 1
	fi

	if ! extract_archive "$archive_path" "$extract_dir"; then
		echo "main:: failed to extract source archive" >&2
		return 1
	fi

	source_dir=""
	for cand in "${extract_dir}"/send-to-slack-*; do
		if [[ -d "$cand" ]]; then
			source_dir="$cand"
			break
		fi
	done
	if [[ -z "$source_dir" ]]; then
		echo "main:: failed to find extracted source directory" >&2
		return 1
	fi

	print_install_info "$source_dir" "$git_ref"

	if ! install_from_source "$source_dir" "$prefix" "$force"; then
		return 1
	fi

	print_next_steps "$prefix"
	if ! verify_installation "$prefix"; then
		echo "main:: installation verification failed: command not found" >&2
		return 1
	fi
	return 0
}

# When piped: BASH_SOURCE[0] may be empty, /dev/stdin, -, or not a file
if [[ "${BASH_SOURCE[0]}" != "$0" ]] && [[ -f "${BASH_SOURCE[0]}" ]]; then
	# Script is being sourced, do not run main
	:
	return 0
fi

set -eo pipefail
umask 077
main "$@"
exit $?
