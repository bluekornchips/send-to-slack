#!/usr/bin/env bash
#
# Detect changed shell files and run corresponding bats tests
# If a source file changes, finds test files that reference it
# If a test file changes, runs that test file directly
#
set -eo pipefail

BASE_BRANCH="main"
DIFF_FILTER="ACMR" # Added, Copied, Modified, Renamed
TEST_DIRS=("tests" "concourse/resource-type/tests")
FILE_EXTENSIONS="sh|bats"

# Filter changed files and find corresponding test files
#
# Inputs:
# - $1 changed files, newline-separated
#
# Returns test files via echo, newline-separated
filter_files() {
	local changed_files
	local file
	local basename
	local test_dir
	local file_ext
	local in_test_dir

	changed_files="${1}"

	if [[ -z "${changed_files}" ]]; then
		echo "filter_files:: changed_files is not set" >&2
		return 1
	fi

	while IFS= read -r file; do
		if [[ ! -f "${file}" ]]; then
			continue
		fi

		# Determine if the changed file is within one of the TEST_DIRS
		in_test_dir=0
		for test_dir in "${TEST_DIRS[@]}"; do
			if [[ "${file}" =~ ^${test_dir}/ ]]; then
				in_test_dir=1
				break
			fi
		done

		# Case 1: Changed file is a test file in TEST_DIRS
		# If the file is in TEST_DIRS and matches the test file pattern (*-tests.sh or *-tests.bats),
		# add it directly to the list of test files to run.
		if ((in_test_dir == 1)) && [[ "${file}" =~ -tests\.(sh|bats)$ ]]; then
			echo "${file}"
		# Case 2: Changed file is a source file (not in TEST_DIRS)
		# If the file is outside TEST_DIRS, it's a source file. Find test files in TEST_DIRS that
		# reference this source file by searching for the basename or full path.
		elif ((in_test_dir == 0)); then
			file_ext="${file##*.}"
			basename=$(basename "${file}" ".${file_ext}")
			find "${TEST_DIRS[@]}" -name "*-tests.${file_ext}" -type f -exec grep -l "${basename}\|${file}" {} \;
		fi
	done <<<"${changed_files}" | sort -u

	return 0
}

# Check for required external commands
#
# Returns:
#   0 if all dependencies are available
#   1 if any dependency is missing
check_dependencies() {
	local missing_deps=()
	local required_commands=("git" "bats" "find" "grep")

	for cmd in "${required_commands[@]}"; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			missing_deps+=("$cmd")
		fi
	done

	if [[ ${#missing_deps[@]} -gt 0 ]]; then
		echo "check_dependencies:: missing required dependencies: ${missing_deps[*]}" >&2
		echo "check_dependencies:: please install missing dependencies and try again" >&2
		return 1
	fi

	return 0
}

main() {
	local base_ref
	local all_changed_sh
	local test_files
	local test_files_list

	if ! check_dependencies; then
		return 1
	fi

	if [[ -n "${GITHUB_BASE_REF}" ]]; then
		base_ref="${GITHUB_BASE_REF}"
		if ! git fetch origin "${base_ref}" 2>/dev/null; then
			echo "main:: Failed to fetch origin/${base_ref}" >&2
			return 1
		fi
		base_ref="origin/${base_ref}"
	else
		base_ref="${BASE_BRANCH}"
	fi

	all_changed_sh=$(git diff --name-only --diff-filter="${DIFF_FILTER}" "${base_ref}..HEAD" |
		grep -E "\.(${FILE_EXTENSIONS})$" || true)

	if [[ -z "${all_changed_sh}" ]]; then
		echo "main:: No shell files changed, skipping tests" >&2
		return 0
	fi

	if ! test_files=$(filter_files "${all_changed_sh}"); then
		echo "main:: filter_files failed" >&2
		return 1
	fi

	if [[ -z "${test_files}" ]]; then
		echo "main:: No test files to run, skipping tests" >&2
		return 0
	fi

	echo "main:: Test files to run:" >&2
	echo "${test_files}" >&2

	test_files_list="${test_files//$'\n'/ }"
	# shellcheck disable=SC2086
	if ! bats --timing --verbose-run ${test_files_list}; then
		echo "main:: bats tests failed" >&2
		return 1
	fi

	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
	exit $?
fi
