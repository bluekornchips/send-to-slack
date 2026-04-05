#!/usr/bin/env bash
#
# Parse payload and build Slack API message JSON
# Composes lib/parse/payload.sh and lib/parse/blocks.sh
#

_PARSE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=parse/payload.sh
source "${_PARSE_LIB_DIR}/parse/payload.sh"
# shellcheck source=parse/blocks.sh
source "${_PARSE_LIB_DIR}/parse/blocks.sh"
unset _PARSE_LIB_DIR
