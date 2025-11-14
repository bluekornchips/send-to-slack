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
	printf '%s\n' \
		"usage: $0 <prefix>" \
		"  e.g. $0 /usr/local" \
		"       $0 ~/.local" >&2
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
# - $1 - prefix: Installation prefix directory
#
# Returns:
# - 0 on success
# - 1 on failure
main() {
	local script_root
	local prefix

	script_root="${0%/*}"
	prefix="${1%/}"

	if [[ -z "$prefix" ]]; then
		usage
		return 1
	fi

	if ! validate_prerequisites "$script_root"; then
		return 1
	fi

	if ! install_files "$script_root" "$prefix"; then
		return 1
	fi

	echo "Installed send-to-slack to $prefix/bin/send-to-slack"

	return 0
}

# Only run main when script is executed directly, not when sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
	exit $?
fi
