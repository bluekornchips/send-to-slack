#!/usr/bin/env bash
#
# Detect changed shell files and run corresponding bats tests
# If a source file changes, finds test files that reference it
# If a test file changes, runs that test file directly
#
set -eo pipefail

BASE_BRANCH="main"
DIFF_FILTER="ACMR"
TEST_DIRS=("tests" "concourse/resource-type/tests")

main() {
	local base_ref
	local current_branch
	local all_changed_sh
	local file
	local basename

	if [[ -n "${GITHUB_BASE_REF}" ]]; then
		base_ref="${GITHUB_BASE_REF}"
		git fetch origin "${base_ref}"
	else
		current_branch=$(git rev-parse --abbrev-ref HEAD)
		base_ref="${BASE_BRANCH}"
		git fetch origin "${base_ref}" || true
		echo "shell-tests:: Running locally: comparing ${current_branch} to origin/${base_ref}"
	fi

	all_changed_sh=$(git diff --name-only --diff-filter="${DIFF_FILTER}" "origin/${base_ref}..HEAD" | grep -E '\.sh$' || true)

	if [[ -z "${all_changed_sh}" ]]; then
		echo "shell-tests:: No shell files changed, skipping tests"
		return 0
	fi

	local test_files
	test_files=$(while IFS= read -r file; do
		if [[ "${file}" =~ -tests\.sh$ ]]; then
			echo "${file}"
		else
			basename=$(basename "${file}" .sh)
			find "${TEST_DIRS[@]}" -name "*-tests.sh" -type f -exec grep -l "${basename}\|${file}" {} \;
		fi
	done <<<"${all_changed_sh}" | sort -u)

	if [[ -z "${test_files}" ]]; then
		echo "shell-tests:: No test files to run, skipping tests"
		return 0
	fi

	echo -e "\n\nshell-tests:: Test files to run:"
	echo "${test_files}"
	bats --timing --verbose-run "${test_files}"

	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
	exit $?
fi
