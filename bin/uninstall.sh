#!/usr/bin/env bash
#
# Uninstall script for send-to-slack
# Removes installation directory matching repo structure
#
set -eo pipefail

usage() {
	cat <<EOF >&2
usage: $0 [--force] [<prefix>]

If prefix is provided, uninstalls from <prefix>/send-to-slack
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

find_installation_prefix() {
	local send_to_slack_cmd
	local resolved_path
	local install_dir
	local prefix

	if ! send_to_slack_cmd=$(command -v send-to-slack 2>/dev/null); then
		echo "find_installation_prefix:: send-to-slack command not found in PATH" >&2
		return 1
	fi

	if ! resolved_path=$(resolve_path "$send_to_slack_cmd"); then
		echo "find_installation_prefix:: failed to resolve path: $send_to_slack_cmd" >&2
		return 1
	fi

	# Resolved path is $prefix/send-to-slack/send-to-slack
	# Get directory: $prefix/send-to-slack
	install_dir=$(cd "$(dirname "$resolved_path")" && pwd)

	# Get prefix: parent of send-to-slack directory
	prefix=$(dirname "$install_dir")
	echo "$prefix"
	return 0
}

main() {
	local force="false"
	local prefix=""

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

	if [[ -n "$prefix" ]]; then
		prefix=$(cd "$prefix" && pwd)
	else
		if ! prefix=$(find_installation_prefix); then
			echo "uninstall:: failed to find installation prefix" >&2
			return 1
		fi
	fi

	local install_dir="${prefix}/send-to-slack"
	local bin_symlink="${prefix}/bin/send-to-slack"

	if [[ ! -d "$install_dir" ]]; then
		echo "uninstall:: installation directory not found: $install_dir" >&2
		return 1
	fi

	if [[ ! -f "$install_dir/send-to-slack" ]]; then
		echo "uninstall:: executable not found: $install_dir/send-to-slack" >&2
		return 1
	fi

	if [[ ! -d "$install_dir/lib" ]]; then
		echo "uninstall:: lib directory not found: $install_dir/lib" >&2
		return 1
	fi

	if is_protected_prefix "$prefix" && [[ "$force" != "true" ]]; then
		echo "uninstall:: refusing to uninstall from protected prefix: $prefix (use --force to override)" >&2
		return 1
	fi

	rm -f "$bin_symlink"
	echo "uninstall:: removed symlink: $bin_symlink"

	rm -rf "$install_dir"
	echo "uninstall:: removed installation directory: $install_dir"

	echo "Uninstalled send-to-slack from $prefix"

	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	if ! main "$@"; then
		exit 1
	fi
	exit 0
fi
