# CI Scripts

## run-bats.sh

Detects changed shell files and runs corresponding bats tests.

### Behavior

- If a test file changes (matches `*-tests.sh` or `*-tests.bats`), runs that test file directly
- If a source file changes, searches test files in `TEST_DIRS` for references to the changed file
- Test files are matched by searching for the basename or full path of the changed file
- Only processes files matching `FILE_EXTENSIONS` (default: `sh|bats`)
- Only includes test files within `TEST_DIRS`

### Usage

#### GitHub Actions

The script runs automatically in GitHub Actions workflows. Set `GITHUB_BASE_REF` to the base branch for comparison.

#### Local Development

Run the script directly:

```bash
./ci/run-bats.sh
```

When run locally without `GITHUB_BASE_REF`, the script compares the current branch to `origin/main`.

### Configuration

Constants at the top of the script:

- `BASE_BRANCH`: Default branch for local comparisons (default: `"main"`)
- `DIFF_FILTER`: Git diff filter for changed files (default: `"ACMR"` - Added, Copied, Modified, Renamed)
- `TEST_DIRS`: Array of directories containing test files (default: `("tests" "concourse/resource-type/tests")`)
- `FILE_EXTENSIONS`: Pipe-separated list of file extensions to process (default: `"sh|bats"`)

Always fetches the base branch from origin before comparing.

### Examples

If `bin/parse-payload.sh` changes, the script finds `tests/parse-payload-tests.sh` because it contains "parse-payload".

If `bin/blocks/rich-text.sh` changes, the script finds `tests/blocks/rich-text-tests.sh` because it contains "rich-text".

If `tests/smoke-tests.sh` changes, the script runs that test file directly.
