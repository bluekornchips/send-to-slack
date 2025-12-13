#!/usr/bin/env bash
#
# Uninstall script for send-to-slack using install manifest
#
set -eo pipefail

usage() {
	printf '%s\n' \
		"usage: $0 [--force] <prefix>" \
		"  e.g. $0 /usr/local" \
		"       $0 ~/.local" >&2
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

main() {
	local prefix=""
	local force="false"
	local manifest_path

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--force)
			force="true"
			shift
			;;
		*)
			prefix="${1%/}"
			shift
			;;
		esac
	done

	if [[ -z "$prefix" ]]; then
		usage
		return 1
	fi

	if is_protected_prefix "$prefix" && [[ "$force" != "true" ]]; then
		echo "uninstall:: refusing to uninstall from protected prefix: $prefix (use --force to override)" >&2
		return 1
	fi

	manifest_path="$prefix/lib/send-to-slack/install_manifest.txt"
	if [[ ! -f "$manifest_path" ]]; then
		echo "uninstall:: manifest not found: $manifest_path" >&2
		return 1
	fi

	if [[ ! -r "$manifest_path" ]]; then
		echo "uninstall:: manifest not readable: $manifest_path" >&2
		return 1
	fi

	while IFS= read -r entry; do
		if [[ -z "$entry" ]]; then
			continue
		fi

		if [[ -f "$entry" || -L "$entry" ]]; then
			rm -f "$entry"
		elif [[ -d "$entry" ]]; then
			rmdir "$entry" 2>/dev/null || true
		else
			echo "uninstall:: skipped missing entry: $entry" >&2
		fi
	done <"$manifest_path"

	rm -f "$manifest_path"

	if [[ -d "$prefix/lib/send-to-slack/bin/blocks" ]]; then
		rmdir "$prefix/lib/send-to-slack/bin/blocks" 2>/dev/null || true
	fi
	if [[ -d "$prefix/lib/send-to-slack/bin" ]]; then
		rmdir "$prefix/lib/send-to-slack/bin" 2>/dev/null || true
	fi
	if [[ -d "$prefix/lib/send-to-slack" ]]; then
		rmdir "$prefix/lib/send-to-slack" 2>/dev/null || true
	fi

	echo "Uninstalled send-to-slack from $prefix"

	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	if ! main "$@"; then
		exit 1
	fi
	exit 0
fi
