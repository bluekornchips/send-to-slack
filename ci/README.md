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

If `lib/parse-payload.sh` changes, the script finds `tests/parse-payload-tests.sh` because it contains "parse-payload".

If `lib/blocks/rich-text.sh` changes, the script finds `tests/blocks/rich-text-tests.sh` because it contains "rich-text".

If `tests/smoke-tests.sh` changes, the script runs that test file directly.

## build.sh

Builds the send-to-slack Docker image and optionally runs checks and produces release artifacts.

### Behavior

- Builds `Docker/Dockerfile` for `linux/amd64`
- Optional healthcheck using `./bin/send-to-slack.sh --health-check`
- Optional test message via `./bin/send-to-slack.sh --file <payload>`
- Optional release artifact tarball (same format used in GitHub Releases)
- Supports GitHub Actions mode (`--gha`) to extract repo/branch metadata

### Usage

Build only:

```bash
./ci/build.sh
```

Build + healthcheck + test message (requires CHANNEL and SLACK_BOT_USER_OAUTH_TOKEN):

```bash
CHANNEL=#test SLACK_BOT_USER_OAUTH_TOKEN=token ./ci/build.sh --healthcheck --send-test-message
```

Build artifact only:

```bash
./ci/build.sh --build-artifact
```

Build artifact with explicit version/output:

```bash
./ci/build.sh --build-artifact --artifact-version v0.1.3 --artifact-output ./artifacts
```

GitHub Actions mode:

```bash
./ci/build.sh --gha
```

### Options

- `--gha` Enable GitHub Actions metadata extraction
- `--no-cache` Disable Docker build cache
- `--healthcheck` Run local health check after build
- `--send-test-message` Send a test message after build (requires CHANNEL and SLACK_BOT_USER_OAUTH_TOKEN)
- `--build-artifact` Produce release tarball(s) into `--artifact-output` (default: ./artifacts)
- `--artifact-version <tag>` Version to embed in artifact name (default: read from VERSION)
- `--artifact-output <dir>` Output directory for artifacts (default: ./artifacts)
- `-h, --help` Show help

### Environment Variables

- `DOCKER_IMAGE_NAME` (default: send-to-slack)
- `DOCKER_IMAGE_TAG` (default: local)
- `NO_CACHE` (default: true)
- `CHANNEL`, `SLACK_BOT_USER_OAUTH_TOKEN` (required for `--send-test-message`)
- `ARTIFACT_VERSION`, `ARTIFACT_OUTPUT` (defaults noted above)

### GitHub Actions variables (used with `--gha`)

- `GITHUB_EVENT_NAME`, `GITHUB_HEAD_REF`, `GITHUB_REF_NAME`, `GITHUB_SHA`, `GITHUB_REPOSITORY`, `GITHUB_SERVER_URL`, `GITHUB_RUN_ID`, `GITHUB_EVENT_PULL_REQUEST_NUMBER`, `GITHUB_EVENT_PULL_REQUEST_HTML_URL`

### Notes

- build-verification.sh and notification.json are removed; the test-message flow now lives behind `--send-test-message`.
