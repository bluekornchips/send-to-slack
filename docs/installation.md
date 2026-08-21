# Installation

Install, uninstall, or run `send-to-slack` from a checkout or container.

## Run from a checkout

```bash
git clone https://github.com/bluekornchips/send-to-slack.git
cd send-to-slack
./bin/send-to-slack.sh -h
```

Optional: `alias send-to-slack="$(pwd)/bin/send-to-slack.sh"`. The script finds `lib/` relative to itself.

## Install

Remote (default branch on GitHub):

```bash
curl -fsSL https://raw.githubusercontent.com/bluekornchips/send-to-slack/main/bin/install.sh | bash
```

From a clone:

```bash
./bin/install.sh
./bin/install.sh --version local   # use this working tree, no GitHub fetch
```

Defaults:

- Prefix: `${HOME}/.local/bin`, or `/usr/local/bin` as root
- Override with `--prefix <dir>` or `--prefix=<dir>`
- Refuses `/usr` and `/etc` paths except `/usr/local`
- Needs `git`, or both `curl` and `tar`, after the install script is downloaded
- Set `GITHUB_REPO=owner/repo` to install from a fork

Other options: `--version <ref>` (default `main`; `local` only works from a checkout, not from `curl | bash`), `--force` (overwrite an unsigned shim).

```bash
# Custom prefix, then PATH if needed
curl -fsSL https://raw.githubusercontent.com/bluekornchips/send-to-slack/main/bin/install.sh | \
  bash -s -- --prefix=/tmp/send-to-slack/bin
export PATH="${HOME}/.local/bin:${PATH}"
```

The installer copies the CLI, `lib/`, and helpers into an install root, symlinks `send-to-slack` into the prefix, and appends a signature used by uninstall.

## Uninstall

```bash
./bin/uninstall.sh
```

Removes the signed shim only; use `--force` to remove an unsigned file. No-op if already absent.

## Containers

```bash
docker pull sunflowersoftware/send-to-slack
```

Dockerfiles under `Docker/`: default, `concourse`, `test`, and `remote`. Build and CI details: [CI Scripts](../ci/README.md). Local Concourse: [Concourse](concourse.md).
