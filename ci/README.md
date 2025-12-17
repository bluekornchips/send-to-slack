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

Builds the send-to-slack Docker image from the Dockerfile.

### Behavior

- Builds a Docker image with the specified name and tag
- Supports GitHub Actions mode (`--gha`) which extracts metadata from GitHub Actions environment variables
- In GitHub Actions mode, exports environment variables for use in notification templates
- Always builds for `linux/amd64` platform

### Usage

#### Local Development

Build with default settings:

```bash
./ci/build.sh
```

Build with custom image name and tag:

```bash
DOCKER_IMAGE_NAME=myimage DOCKER_IMAGE_TAG=v1.0.0 ./ci/build.sh
```

#### GitHub Actions

Build with GitHub Actions mode enabled:

```bash
./ci/build.sh --gha
```

When `--gha` is used, the script extracts metadata from GitHub Actions environment variables and exports them for use in notification templates.

### Environment Variables

- `DOCKER_IMAGE_NAME`: Image name (default: `send-to-slack`)
- `DOCKER_IMAGE_TAG`: Image tag (default: `local`)

#### GitHub Actions Variables (only used with `--gha` flag)

- `GITHUB_EVENT_NAME`: Event type (pull_request, push, etc.)
- `GITHUB_HEAD_REF`: Branch name for pull requests
- `GITHUB_REF_NAME`: Branch name for pushes
- `GITHUB_EVENT_PULL_REQUEST_NUMBER`: PR number
- `GITHUB_EVENT_PULL_REQUEST_HTML_URL`: PR URL
- `GITHUB_SHA`: Commit SHA
- `GITHUB_REPOSITORY`: Repository name
- `GITHUB_SERVER_URL`: GitHub server URL
- `GITHUB_RUN_ID`: Workflow run ID

### Exported Variables (GitHub Actions mode)

When `--gha` is used, the following variables are exported for use in notification templates:

- `EVENT_TYPE`: "Pull Request" or "Push"
- `BRANCH`: Branch name
- `COMMIT_SHA`: Full commit SHA
- `COMMIT_SHORT`: Short commit SHA (first 7 characters)
- `PR_NUMBER`: Pull request number (if applicable)
- `PR_URL`: Pull request URL (if applicable)
- `TIMESTAMP`: UTC timestamp
- `WORKFLOW_RUN_URL`: URL to the workflow run
- `REPO`: Repository name

## build-verification.sh

Located at `ci/build-verification.sh`. Verifies the built container works by sending a test notification to Slack.

### Behavior

- Builds the Docker image using `build.sh`
- Processes `notification.json` template with environment variable substitution
- Adds GitHub Actions context block if running in GitHub Actions
- Sends a test notification to the specified Slack channel using the built image
- Automatically detects GitHub Actions environment and uses appropriate build mode

### Usage

#### Local Development

Build and send test notification:

```bash
CHANNEL=#test SLACK_BOT_USER_OAUTH_TOKEN=token ./ci/build-verification.sh
```

Build and test with custom tag:

```bash
CHANNEL=#test SLACK_BOT_USER_OAUTH_TOKEN=token ./ci/build-verification.sh --tag v1.0.0
```

Test using an existing image by ID:

```bash
CHANNEL=#test SLACK_BOT_USER_OAUTH_TOKEN=token ./ci/build-verification.sh --image efa4fc963b0e
```

Test using a full image reference:

```bash
CHANNEL=#test SLACK_BOT_USER_OAUTH_TOKEN=token ./ci/build-verification.sh --tag registry/repo:tag
```

#### GitHub Actions

The script automatically detects GitHub Actions environment and uses `--gha` mode when building.

### Options

- `-t, --tag TAG`: Docker image tag or full image:tag reference (default: `local`)
  - Tag: `v1.0.0` (uses `DOCKER_IMAGE_NAME`)
  - Full reference: `registry/repo:tag` (used directly)
- `-i, --image IMAGE_ID`: Docker image ID to use for testing (overrides `-t/--tag`)
- `-h, --help`: Show help message

### Environment Variables

- `CHANNEL`: Required - Slack channel to send notification to
- `SLACK_BOT_USER_OAUTH_TOKEN`: Required - Slack OAuth token
- `DOCKER_IMAGE_NAME`: Image name (default: `send-to-slack`)
- `DOCKER_IMAGE_TAG`: Image tag (default: `local`, overridden by `-t/--tag`)
- `DOCKER_IMAGE_ID`: Image ID (overridden by `-i/--image`)

### Local Development Metadata

When not running in GitHub Actions, the script automatically extracts:

- `BRANCH`: Current git branch
- `COMMIT_SHA`: Current commit SHA
- `COMMIT_SHORT`: Short commit SHA (first 7 characters)
- `TIMESTAMP`: Current UTC timestamp
- `REPO`: Repository name from git remote

These are exported and used in the `notification.json` template.

## notification.json

Template file for build test notifications.

### Behavior

- Uses environment variable substitution with `envsubst`
- Contains Slack block structure for build notifications
- Variables are substituted at runtime by `ci/build-verification.sh`

### Template Variables

- `${BRANCH}`: Branch name
- `${COMMIT_SHORT}`: Short commit SHA
- `${TIMESTAMP}`: UTC timestamp

### Usage

This file is automatically processed by `ci/build-verification.sh` when sending test notifications. The template is expanded with environment variables before being sent to Slack.
