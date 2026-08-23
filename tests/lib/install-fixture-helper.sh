#!/usr/bin/env bash
#
# Shared helpers for install/uninstall Bats fixtures
#

# Copy the real product tree into a temporary source directory
#
# Arguments:
#   $1 - destination source directory
#   $2 - git root containing bin/ and lib/
#
# Returns:
#   0 on success
#   1 on failure
install_fixture_copy_product_tree() {
	local dest_dir="$1"
	local git_root="$2"

	if [[ -z "$dest_dir" || -z "$git_root" ]]; then
		echo "install_fixture_copy_product_tree:: destination and git root are" \
			"required" >&2
		return 1
	fi

	mkdir -p "${dest_dir}/bin" "${dest_dir}/lib"

	if ! cp "${git_root}/bin/send-to-slack.sh" "${dest_dir}/bin/send-to-slack.sh"; then
		return 1
	fi

	if ! cp -a "${git_root}/lib/." "${dest_dir}/lib/"; then
		return 1
	fi

	if [[ -f "${git_root}/VERSION" ]]; then
		cp "${git_root}/VERSION" "${dest_dir}/VERSION"
	fi

	return 0
}

# Assert the installed tree contains every module in SEND_TO_SLACK_LIB_MANIFEST
#
# Arguments:
#   $1 - install root containing send-to-slack and lib/
#
# Returns:
#   0 when complete
#   1 when incomplete
install_fixture_assert_manifest() {
	local install_root="$1"
	local loader_file
	local rel
	local abs

	if [[ -z "$install_root" || ! -d "$install_root" ]]; then
		echo "install_fixture_assert_manifest:: install root not found" >&2
		return 1
	fi

	loader_file="${install_root}/lib/loader.sh"
	if [[ ! -f "$loader_file" ]]; then
		echo "install_fixture_assert_manifest:: missing lib/loader.sh" >&2
		return 1
	fi

	# shellcheck source=lib/loader.sh
	source "$loader_file"

	for rel in "${SEND_TO_SLACK_LIB_MANIFEST[@]}"; do
		abs="${install_root}/lib/${rel}"
		if [[ ! -f "$abs" ]]; then
			echo "install_fixture_assert_manifest:: missing lib/${rel}" >&2
			return 1
		fi
	done

	return 0
}
