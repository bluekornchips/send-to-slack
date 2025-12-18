#!/usr/bin/env bash
#
# Uninstall helper for send-to-slack
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_PREFIX="${HOME}/.local/bin"
INSTALL_BASENAME="send-to-slack"
INSTALL_SIGNATURE="# send-to-slack install signature: v1"

# Display usage information
#
# Side Effects:
# - Outputs usage details to stdout
# Returns:
# - 0 always
usage() {
	cat <<EOF
Usage: $(basename "$0") [--prefix <dir>] [--force] [--help]

Options:
  --prefix <dir>   Target directory for removal (default: ${DEFAULT_PREFIX})
  --force          Remove file even without signature
  -h, --help       Show this help message

Behavior:
  - Removes the installed send-to-slack shim when it carries the install signature
  - Refuses system prefixes like /usr or /etc; choose a writable user path
  - No-op if the target file does not exist
EOF
	return 0
}

# Validate required external commands
# Returns:
# - 0 on success, 1 on missing commands
check_dependencies() {
	local missing=()
	local commands=("rm" "grep")
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
# Inputs:
# - $1 - path to normalize
# Outputs:
# - normalized path to stdout
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

# Check for install signature on an existing file
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

# Validate prefix is acceptable for uninstall actions
# Inputs:
# - $1 - prefix
# Returns:
# - 0 on success, 1 on failure
validate_prefix() {
	local prefix="$1"

	if [[ -z "$prefix" ]]; then
		echo "validate_prefix:: prefix is empty" >&2
		return 1
	fi

	case "$prefix" in
	/usr/* | /etc/*)
		echo "validate_prefix:: refusing system prefix: $prefix" >&2
		return 1
		;;
	esac

	return 0
}

# Uninstall binary guarded by signature unless forced
# Inputs:
# - $1 - prefix
# - $2 - force flag (1 allows unsigned removal)
# Returns:
# - 0 on success, 1 on failure
uninstall_binary() {
	local prefix="$1"
	local force="$2"
	local normalized_prefix
	local target

	if ! normalized_prefix=$(normalize_prefix "$prefix"); then
		return 1
	fi

	target="${normalized_prefix}/${INSTALL_BASENAME}"

	if [[ ! -e "$target" ]]; then
		echo "uninstall_binary:: no file to remove at $target"
		return 0
	fi

	if [[ -d "$target" ]]; then
		echo "uninstall_binary:: target is a directory, aborting: $target" >&2
		return 1
	fi

	if ((force != 1)) && ! file_has_signature "$target"; then
		echo "uninstall_binary:: missing signature, refusing removal (use --force to override): $target" >&2
		return 1
	fi

	if ! rm -f "$target"; then
		echo "uninstall_binary:: failed to remove $target" >&2
		return 1
	fi

	echo "uninstall_binary:: removed $target"
	return 0
}

main() {
	local prefix
	local force

	prefix="$DEFAULT_PREFIX"
	force=0

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

	if ! check_dependencies; then
		return 1
	fi

	if ! validate_prefix "$prefix"; then
		return 1
	fi

	if ! uninstall_binary "$prefix" "$force"; then
		return 1
	fi

	return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	main "$@"
	exit $?
fi
