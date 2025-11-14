#!/usr/bin/env bash

set -eo pipefail

PREFIX="${1%/}"

if [[ -z "$PREFIX" ]]; then
	printf '%s\n' \
		"usage: $0 <prefix>" \
		"  e.g. $0 /usr/local" \
		"       $0 ~/.local" >&2
	exit 1
fi

if [[ ! -f "$PREFIX/bin/send-to-slack" ]]; then
	echo "uninstall:: send-to-slack not found at $PREFIX/bin/send-to-slack" >&2
	exit 1
fi

# Remove support files (parse-payload.sh, file-upload.sh, etc.)
for file in "$PREFIX/bin"/*.sh; do
	if [[ -f "$file" ]] && [[ "$(basename "$file")" != "send-to-slack" ]]; then
		rm -f "$file"
	fi
done

# Remove blocks directory if it exists
if [[ -d "$PREFIX/bin/blocks" ]]; then
	rm -rf "$PREFIX/bin/blocks"
fi

rm -f "$PREFIX/bin/send-to-slack"

echo "Uninstalled send-to-slack from $PREFIX"
