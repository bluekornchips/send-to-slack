#!/usr/bin/env bash
#
# Install helper for send-to-slack
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPSTREAM_REPO="bluekornchips/send-to-slack"
SOURCE_SCRIPT="${SCRIPT_DIR}/send-to-slack.sh"
DEFAULT_PREFIX="${HOME}/.local/bin"
# Default to /usr/local/bin for root so the binary lands on PATH in containers.
if [[ "$(id -u)" -eq 0 ]]; then
	DEFAULT_PREFIX="/usr/local/bin"
fi
INSTALL_BASENAME="send-to-slack"
INSTALL_SIGNATURE="# send-to-slack install signature: v1"
GITHUB_REPO="${GITHUB_REPO:-${UPSTREAM_REPO}}"

# Display usage information
#
# Side Effects:
# - Outputs usage details to stdout
#
# Returns:
# - 0 always
usage() {
	cat <<EOF
Usage: $(basename "$0") [--prefix <dir>] [--force] [--version <tag>|local] [--help]

Options:
  --prefix <dir>   Target directory for installation (default: ${DEFAULT_PREFIX})
  --force          Overwrite existing file even if unsigned
  --version <tag>  Install from specific branch/tag (default: main). Use "local" to install from the current repo.
  -h, --help       Show this help message

Behavior:
  - Copies bin/send-to-slack.sh to the target directory as "send-to-slack"
  - Appends a signature comment for safe uninstall validation
  - Refuses system prefixes like /usr or /etc; choose a writable user path
  - Creates the prefix if missing and sets mode 0755 on the installed file
EOF
	return 0
}

# Validate required external commands
#
# Returns:
# - 0 on success, 1 on missing commands
check_dependencies() {
	local missing=()
	local commands=("unzip")
	local cmd

	for cmd in "${commands[@]}"; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			missing+=("$cmd")
		fi
	done

	if [[ ${#missing[@]} -gt 0 ]]; then
		echo "check_dependencies:: missing commands: ${missing[*]}" >&2
		return 1
	fi

	return 0
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

# Verify source script exists and is readable
# Returns:
# - 0 on success, 1 on failure
ensure_source() {
	if [[ ! -f "$SOURCE_SCRIPT" ]]; then
		echo "ensure_source:: source missing: $SOURCE_SCRIPT" >&2
		return 1
	fi

	if [[ ! -r "$SOURCE_SCRIPT" ]]; then
		echo "ensure_source:: source not readable: $SOURCE_SCRIPT" >&2
		return 1
	fi

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

# Install binary to prefix with signature and mode
#
# Inputs:
# - $1 - prefix
# - $2 - force flag (1 enables overwrite without signature)
# Returns:
# - 0 on success, 1 on failure
install_binary() {
	local prefix="$1"
	local force="$2"
	local normalized_prefix
	local target

	if ! normalized_prefix=$(normalize_prefix "$prefix"); then
		return 1
	fi

	target="${normalized_prefix}/${INSTALL_BASENAME}"

	if [[ -d "$target" ]]; then
		echo "install_binary:: target is a directory: $target" >&2
		return 1
	fi

	if [[ -f "$target" ]] && ((force != 1)); then
		if ! file_has_signature "$target"; then
			echo "install_binary:: existing file lacks signature, use --force to overwrite: $target" >&2
			return 1
		fi
	fi

	if ! cp "$SOURCE_SCRIPT" "$target"; then
		echo "install_binary:: copy failed to $target" >&2
		return 1
	fi

	if ! chmod 0755 "$target"; then
		echo "install_binary:: chmod failed on $target" >&2
		return 1
	fi

	if ! printf '\n%s\n' "$INSTALL_SIGNATURE" >>"$target"; then
		echo "install_binary:: failed to append signature to $target" >&2
		return 1
	fi

	if ! file_has_signature "$target"; then
		echo "install_binary:: signature verification failed for $target" >&2
		return 1
	fi

	echo "install_binary:: installed $target"
	return 0
}

# Install from extracted source directory
# Inputs:
# - $1 - source directory path
# - $2 - prefix
# - $3 - force flag (1 enables overwrite without signature)
install_from_source() {
	local source_dir="$1"
	local prefix="$2"
	local force="${3:-0}"
	local normalized_prefix
	local install_root
	local target_binary

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

	if [[ ! -f "${source_dir}/lib/parse-payload.sh" ]]; then
		echo "install_from_source:: missing lib/parse-payload.sh" >&2
		return 1
	fi

	if [[ ! -d "${source_dir}/lib/blocks" ]]; then
		echo "install_from_source:: missing lib/blocks directory" >&2
		return 1
	fi

	install_root="/usr/local/send-to-slack"
	target_binary="${normalized_prefix}/${INSTALL_BASENAME}"

	if [[ -f "$target_binary" ]] && ((force != 1)); then
		if ! file_has_signature "$target_binary"; then
			echo "install_from_source:: existing file lacks signature, use --force to overwrite: $target_binary" >&2
			return 1
		fi
	fi

	if ! install -d -m 755 "${install_root}/lib/blocks" "$(dirname "$target_binary")"; then
		echo "install_from_source:: failed to create installation directories" >&2
		return 1
	fi

	if ! cp "${source_dir}/bin/send-to-slack.sh" "${install_root}/send-to-slack"; then
		echo "install_from_source:: failed to copy script" >&2
		return 1
	fi

	if ! chmod 0755 "${install_root}/send-to-slack"; then
		echo "install_from_source:: failed to chmod script" >&2
		return 1
	fi

	if ! cp "${source_dir}/lib"/*.sh "${install_root}/lib/"; then
		echo "install_from_source:: failed to copy lib files" >&2
		return 1
	fi

	if ! cp "${source_dir}/lib/blocks"/*.sh "${install_root}/lib/blocks/"; then
		echo "install_from_source:: failed to copy lib/blocks files" >&2
		return 1
	fi

	if [[ -L "$target_binary" ]] || [[ -f "$target_binary" ]]; then
		rm -f "$target_binary"
	fi

	if ! ln -sf "${install_root}/send-to-slack" "$target_binary"; then
		echo "install_from_source:: failed to create symlink" >&2
		return 1
	fi

	if ! printf '\n%s\n' "$INSTALL_SIGNATURE" >>"${install_root}/send-to-slack"; then
		echo "install_from_source:: failed to append signature" >&2
		return 1
	fi

	if ! file_has_signature "${install_root}/send-to-slack"; then
		echo "install_from_source:: signature verification failed" >&2
		return 1
	fi

	echo "install_from_source:: installed $target_binary"
	return 0
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
		echo "print_next_steps:: add to PATH: export PATH=\"${normalized_prefix}:\$PATH\""
	fi

	echo "print_next_steps:: installed binary: ${normalized_prefix}/${INSTALL_BASENAME}"
	return 0
}

# Build source archive URL for a branch/tag
build_source_archive_url() {
	local ref="$1"
	local base_url

	base_url="https://github.com/${GITHUB_REPO}/archive/refs/heads/${ref}.zip"
	# If ref looks like a tag (starts with v), use tags instead of heads
	if [[ "$ref" =~ ^v[0-9] ]]; then
		base_url="https://github.com/${GITHUB_REPO}/archive/refs/tags/${ref}.zip"
	fi

	ARTIFACT_URL="$base_url"
	return 0
}

# Download file
download_file() {
	local url="$1"
	local output="$2"

	if ! curl --proto "=https" --tlsv1.2 --fail --show-error --location --output "$output" "$url"; then
		echo "download_file:: failed to download $url" >&2
		return 1
	fi

	return 0
}

main() {
	local prefix
	local force
	local version
	local artifact_url
	local temp_dir
	local zip_path
	local extract_dir
	local source_dir

	prefix="$DEFAULT_PREFIX"
	force=0
	version=""
	artifact_url=""

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
		if ! check_dependencies; then
			return 1
		fi
		if ! ensure_source; then
			return 1
		fi
		if ! ensure_prefix "$prefix"; then
			return 1
		fi
		if ! install_binary "$prefix" "$force"; then
			return 1
		fi
		print_next_steps "$prefix"
		return 0
	fi

	if ! check_dependencies; then
		return 1
	fi

	local git_ref="${version:-main}"

	build_source_archive_url "$git_ref"
	artifact_url="$ARTIFACT_URL"

	if ! ensure_prefix "$prefix"; then
		return 1
	fi

	temp_dir=$(mktemp -d)
	umask 077
	zip_path="${temp_dir}/source.zip"

	if ! download_file "$artifact_url" "$zip_path"; then
		echo "main:: failed to download source archive from ${artifact_url}" >&2
		rm -rf "$temp_dir"
		return 1
	fi

	extract_dir="${temp_dir}/extract"
	if ! mkdir -p "$extract_dir"; then
		echo "main:: failed to create extract directory" >&2
		rm -rf "$temp_dir"
		return 1
	fi

	if ! unzip -q "$zip_path" -d "$extract_dir"; then
		echo "main:: failed to extract source archive" >&2
		rm -rf "$temp_dir"
		return 1
	fi

	source_dir=$(find "$extract_dir" -maxdepth 1 -type d -name "send-to-slack-*" | head -1)
	if [[ -z "$source_dir" ]]; then
		echo "main:: failed to find extracted source directory" >&2
		rm -rf "$temp_dir"
		return 1
	fi

	if ! install_from_source "$source_dir" "$prefix" "$force"; then
		rm -rf "$temp_dir"
		return 1
	fi

	rm -rf "$temp_dir"
	print_next_steps "$prefix"
	return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	main "$@"
	exit $?
fi
