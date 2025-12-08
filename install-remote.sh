#!/usr/bin/env bash
#
# Remote installer for send-to-slack
# This script can be called directly via curl:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/bluekornchips/send-to-slack/main/install-remote.sh)"
#
set -eo pipefail

########################################################
# Configuration
########################################################
REPO_URL="https://github.com/bluekornchips/send-to-slack.git"
REPO_BRANCH="${INSTALL_BRANCH:-main}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local}"

########################################################
# Colors for output (optional, will work without them)
########################################################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print colored message
print_message() {
	local color="$1"
	local message="$2"
	if [[ -t 1 ]]; then
		echo -e "${color}${message}${NC}"
	else
		echo "$message"
	fi
}

# Print error message
print_error() {
	print_message "$RED" "$1" >&2
}

# Print success message
print_success() {
	print_message "$GREEN" "$1"
}

# Print warning message
print_warning() {
	print_message "$YELLOW" "$1"
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
		print_error "ERROR: Unable to determine bash version"
		return 1
	fi

	if [[ $major_version -lt 4 ]] || ([[ $major_version -eq 4 ]] && [[ $minor_version -lt 0 ]]); then
		print_error "ERROR: Bash 4.0 or later is required (found: $bash_version)"
		return 1
	fi

	return 0
}

# Check all prerequisites
check_prerequisites() {
	local missing_deps=()
	local errors=0

	print_warning "Checking prerequisites..."

	# Check bash version
	if ! check_bash_version; then
		errors=$((errors + 1))
	fi

	# Check for required commands
	if ! command_exists curl; then
		missing_deps+=("curl")
		errors=$((errors + 1))
	fi

	if ! command_exists jq; then
		missing_deps+=("jq")
		errors=$((errors + 1))
	fi

	if ! command_exists git; then
		missing_deps+=("git")
		errors=$((errors + 1))
	fi

	# Report missing dependencies
	if [[ ${#missing_deps[@]} -gt 0 ]]; then
		print_error "ERROR: Missing required dependencies: ${missing_deps[*]}"
		print_error ""
		print_error "Please install the missing dependencies:"
		for dep in "${missing_deps[@]}"; do
			case "$dep" in
			curl)
				print_error "  - curl: https://curl.se/download.html"
				;;
			jq)
				print_error "  - jq: https://github.com/jqlang/jq/releases"
				;;
			git)
				print_error "  - git: https://git-scm.com/downloads"
				;;
			esac
		done
	fi

	if [[ $errors -gt 0 ]]; then
		print_error ""
		print_error "Installation cannot proceed without required dependencies."
		return 1
	fi

	print_success "All prerequisites met"
	return 0
}

# Clone repository to temporary directory
clone_repository() {
	local temp_dir
	temp_dir=$(mktemp -d)
	trap 'rm -rf "$temp_dir"' EXIT

	print_warning "Cloning repository from ${REPO_URL} (branch: ${REPO_BRANCH})..."

	if ! git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$temp_dir" 2>&1; then
		print_error "ERROR: Failed to clone repository"
		return 1
	fi

	echo "$temp_dir"
	return 0
}

# Main installation function
main() {
	local script_dir
	local temp_repo
	local install_script

	print_warning "send-to-slack Remote Installer"
	print_warning "================================"
	echo ""

	# Check prerequisites first
	if ! check_prerequisites; then
		exit 1
	fi

	echo ""
	print_warning "Installation prefix: ${INSTALL_PREFIX}"
	print_warning "Repository branch: ${REPO_BRANCH}"
	echo ""

	# Clone repository
	if ! temp_repo=$(clone_repository); then
		exit 1
	fi

	# Ensure cleanup on exit
	trap 'rm -rf "$temp_repo"' EXIT

	# Check if install.sh exists in cloned repo
	install_script="${temp_repo}/install.sh"
	if [[ ! -f "$install_script" ]]; then
		print_error "ERROR: install.sh not found in repository"
		exit 1
	fi

	# Make install.sh executable
	chmod +x "$install_script"

	echo ""
	print_warning "Installing send-to-slack to ${INSTALL_PREFIX}..."
	echo ""

	# Run the installation script
	# Check if we need sudo for the prefix
	local needs_sudo=false
	if [[ ! -w "$(dirname "$INSTALL_PREFIX")" ]] && [[ "$INSTALL_PREFIX" != "$HOME"* ]]; then
		needs_sudo=true
	fi

	if [[ "$needs_sudo" == "true" ]]; then
		if ! command_exists sudo; then
			print_error "ERROR: sudo is required to install to ${INSTALL_PREFIX} but is not available"
			exit 1
		fi
		if ! sudo "$install_script" "$INSTALL_PREFIX"; then
			print_error "ERROR: Installation failed"
			exit 1
		fi
	else
		if ! "$install_script" "$INSTALL_PREFIX"; then
			print_error "ERROR: Installation failed"
			exit 1
		fi
	fi

	echo ""
	print_success "Installation completed successfully!"
	echo ""
	print_success "send-to-slack has been installed to ${INSTALL_PREFIX}/bin/send-to-slack"
	echo ""
	print_warning "To use send-to-slack, ensure ${INSTALL_PREFIX}/bin is in your PATH"
	echo ""

	# Cleanup
	rm -rf "$temp_repo"
	trap - EXIT

	return 0
}

# Only run main when script is executed directly, not when sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
	exit $?
fi
