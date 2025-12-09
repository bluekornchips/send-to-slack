#!/usr/bin/env bash
#
# Installation script for send-to-slack
# Installs send-to-slack to the specified prefix directory
#
set -eo pipefail

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

	printf '%s\n' "${manifest_entries[@]}" >"$manifest_file"

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
	local manifest_file

	script_root="${0%/*}"
	default_prefix="${HOME}/.local"
	prefix="${1%/}"
	manifest_file=""

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

	if ! validate_prerequisites "$script_root"; then
		return 1
	fi

	manifest_file="$prefix/share/send-to-slack/install_manifest.txt"

	if ! install_files "$script_root" "$prefix" "$manifest_file"; then
		return 1
	fi

	echo "main:: Installed send-to-slack to ${prefix}/bin/send-to-slack"

	return 0
}

# Only run main when script is executed directly, not when sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
	exit $?
fi
