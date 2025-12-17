#!/usr/bin/env bash
#
# Uninstall script for send-to-slack
# Finds installation directory by resolving where send-to-slack command points to
#
set -eo pipefail

usage() {
	cat <<EOF >&2
usage: $0 [--force] [<prefix>]

If prefix is provided, uninstalls from <prefix>/send-to-slack/
If prefix is omitted, finds installation by resolving send-to-slack command location

OPTIONS:
  --force    Allow uninstalling from protected prefixes
  --help     Show this help message

EXAMPLES:
  $0 /usr/local
  $0 ~/.local
  $0
EOF
}

# Check if a prefix path is protected from uninstallation
#
# Arguments:
#   $1 - prefix: Installation prefix path to check
#
# Returns:
#   0 if prefix is protected (requires --force to uninstall)
#   1 if prefix is not protected
is_protected_prefix() {
	local prefix="$1"

	case "$prefix" in
	"/" | "/usr" | "/usr/local" | "/bin" | "/usr/bin")
		return 0
		;;
	*)
		return 1
		;;
	esac
}

# Resolve path following symlinks
#
# Arguments:
#   $1 - path: Path to resolve
#
# Outputs:
#   Writes resolved path to stdout
#
# Returns:
#   0 on success
#   1 on failure
resolve_path() {
	local p="$1"
	if [[ "$p" != */* ]]; then
		p=$(command -v "$p" 2>/dev/null || echo "$p")
	fi

	local count=0
	while [[ -L "$p" && $count -lt 10 ]]; do
		local target
		target=$(readlink "$p")
		if [[ "$target" == /* ]]; then
			p="$target"
		else
			p="$(cd "$(dirname "$p")" && cd "$(dirname "$target")" && pwd)/$(basename "$target")"
		fi
		count=$((count + 1))
	done
	echo "$p"
}

# Find installation directory by resolving send-to-slack command
#
# Outputs:
#   Writes installation directory path to stdout
#
# Returns:
#   0 on success
#   1 if send-to-slack command not found or installation directory cannot be determined
find_installation_directory() {
	local send_to_slack_cmd
	local resolved_path
	local install_dir

	if ! send_to_slack_cmd=$(command -v send-to-slack 2>/dev/null); then
		echo "find_installation_directory:: send-to-slack command not found in PATH" >&2
		return 1
	fi

	if ! resolved_path=$(resolve_path "$send_to_slack_cmd"); then
		echo "find_installation_directory:: failed to resolve path: $send_to_slack_cmd" >&2
		return 1
	fi

	install_dir=$(cd "$(dirname "$resolved_path")" && pwd)

	# If we're in a bin/ directory, check if there's a send-to-slack directory here
	if [[ "$(basename "$install_dir")" == "bin" ]]; then
		if [[ -d "$install_dir/send-to-slack" ]] && [[ -f "$install_dir/send-to-slack/send-to-slack" ]] && [[ -d "$install_dir/send-to-slack/lib" ]]; then
			install_dir="$install_dir/send-to-slack"
		fi
	fi

	if [[ ! -d "$install_dir" ]]; then
		echo "find_installation_directory:: installation directory not found: $install_dir" >&2
		return 1
	fi

	if [[ ! -f "$install_dir/send-to-slack" ]]; then
		echo "find_installation_directory:: send-to-slack executable not found in: $install_dir" >&2
		return 1
	fi

	if [[ ! -d "$install_dir/lib" ]]; then
		echo "find_installation_directory:: lib directory not found in: $install_dir" >&2
		return 1
	fi

	echo "$install_dir"
	return 0
}

main() {
	local force="false"
	local prefix=""
	local install_dir

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--force)
			force="true"
			shift
			;;
		--help | -h)
			usage
			return 0
			;;
		-*)
			echo "uninstall:: unknown option: $1" >&2
			usage
			return 1
			;;
		*)
			if [[ -z "$prefix" ]]; then
				prefix="${1%/}"
			else
				echo "uninstall:: multiple prefix arguments provided" >&2
				usage
				return 1
			fi
			shift
			;;
		esac
	done

	# If prefix provided, use it directly; otherwise find by resolving command
	if [[ -n "$prefix" ]]; then
		install_dir="$prefix/bin/send-to-slack"
		if [[ ! -d "$install_dir" ]]; then
			echo "uninstall:: installation directory not found: $install_dir" >&2
			return 1
		fi
		if [[ ! -f "$install_dir/send-to-slack" ]]; then
			echo "uninstall:: send-to-slack executable not found in: $install_dir" >&2
			return 1
		fi
		if [[ ! -d "$install_dir/lib" ]]; then
			echo "uninstall:: lib directory not found in: $install_dir" >&2
			return 1
		fi
		# Make install_dir absolute for consistent path comparison
		install_dir=$(cd "$install_dir" && pwd)
	else
		if ! install_dir=$(find_installation_directory); then
			echo "uninstall:: failed to find installation directory" >&2
			return 1
		fi
	fi

	prefix=$(dirname "$install_dir")

	if is_protected_prefix "$prefix" && [[ "$force" != "true" ]]; then
		echo "uninstall:: refusing to uninstall from protected prefix: $prefix (use --force to override)" >&2
		return 1
	fi

	# Remove executable copy in bin/ if it exists
	local bin_executable
	bin_executable="$prefix/bin/send-to-slack"
	if [[ -f "$bin_executable" ]]; then
		rm -f "$bin_executable"
		echo "uninstall:: removed executable: $bin_executable"
	fi

	# Remove installation directory
	if [[ -d "$install_dir" ]]; then
		rm -rf "$install_dir"
		echo "uninstall:: removed installation directory: $install_dir"
	fi

	echo "Uninstalled send-to-slack from $install_dir"

	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	if ! main "$@"; then
		exit 1
	fi
	exit 0
fi
