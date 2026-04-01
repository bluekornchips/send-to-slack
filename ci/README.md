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

Builds the send-to-slack Docker image and optionally runs checks.

### Behavior

- Builds `Docker/Dockerfile` for `linux/amd64`
- Optional healthcheck using `./bin/send-to-slack.sh --health-check`
- Optional test message via `./bin/send-to-slack.sh --file <payload>`
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

GitHub Actions mode:

```bash
./ci/build.sh --gha
```

### Options

- `--gha` Enable GitHub Actions metadata extraction
- `--no-cache` Disable Docker build cache
- `--healthcheck` Run local health check after build
- `--send-test-message` Send a test message after build (requires CHANNEL and SLACK_BOT_USER_OAUTH_TOKEN)
- `--dockerfile <name>` Which Dockerfile to build: `concourse`, `test`, `remote`, or `all` (default: `Docker/Dockerfile`)
- `-h, --help` Show help

### Environment Variables

- `DOCKER_IMAGE_NAME` (default: send-to-slack)
- `DOCKER_IMAGE_TAG` (default: local)
- `NO_CACHE` (default: true)
- `CHANNEL`, `SLACK_BOT_USER_OAUTH_TOKEN` (required for `--send-test-message`)

### GitHub Actions variables, used with `--gha`

- `GITHUB_EVENT_NAME`, `GITHUB_HEAD_REF`, `GITHUB_REF_NAME`, `GITHUB_SHA`, `GITHUB_REPOSITORY`, `GITHUB_SERVER_URL`, `GITHUB_RUN_ID`, `GITHUB_EVENT_PULL_REQUEST_NUMBER`, `GITHUB_EVENT_PULL_REQUEST_HTML_URL`

### Notes

- build-verification.sh and notification.json are removed; the test-message flow now lives behind `--send-test-message`.

## run-all-examples.sh

Starts a local Concourse environment, loads all example pipelines from `examples/`, and triggers every job in every pipeline in order, waiting for each to finish. Used for end-to-end validation of all Concourse example configurations.

### Behavior

- Starts Concourse via `docker-compose -f concourse/server.yaml up -d`
- Logs in with `fly` to target `local` (http://localhost:8080, user `local`, password `slacker`)
- For each `*.yaml` in `examples/`, sets the pipeline and unpauses it
- Triggers every job in each pipeline in YAML order with `fly trigger-job -w`; stops on first job failure

### Prerequisites

- Docker and docker-compose (Concourse server)
- `fly` CLI (Concourse client)
- `yq` (YAML parsing for job names)

### Usage

From the repository root:

```bash
export SLACK_BOT_USER_OAUTH_TOKEN="xoxb-your-token"
export CHANNEL="#your-channel"
./ci/run-all-examples.sh
```

Or use the Makefile target:

```bash
make concourse-run-all-examples
```

### Options

- `--start-from <pipeline/job>` Skip all jobs before this one and resume from here
- `-h, --help` Show help

### Environment Variables

- `SLACK_BOT_USER_OAUTH_TOKEN`, required: Slack bot OAuth token for pipeline variables
- `CHANNEL`, required: Primary Slack channel for pipeline variables
- `SIDE_CHANNEL`, optional: Secondary Slack channel, defaults to empty
- `SLACK_WEBHOOK_URL`, optional: Incoming Webhook URL for `examples/webhook-slack.yaml`. When unset, `webhook-slack/notify-via-slack-webhook` is skipped so the suite can still pass without a webhook
- `TAG`, optional: Docker image tag for the resource type, defaults to contents of `VERSION` file

### Notes

- Jobs listed in the hardcoded `SKIPPED_JOBS` array are skipped. This includes `thread-replies/thread-replies-with-thread-ts` and all `video/*` jobs, which need Slack app configuration that a local run may not have.
- When `SLACK_WEBHOOK_URL` is empty, `webhook-slack/notify-via-slack-webhook` is skipped for the same reason.
