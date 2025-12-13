#!/usr/bin/env bash
#
# Build self-contained send-to-slack script
# Creates a single executable that bundles all dependencies
#
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_FILE="${SCRIPT_DIR}/send-to-slack"

echo "Building self-contained send-to-slack..."

# Start the self-contained script
cat > "$OUTPUT_FILE" << 'HEADER'
#!/usr/bin/env bash
#
# send-to-slack - Self-contained Slack notification script
# Requires: bash, curl, jq, gettext (envsubst)
#
set -eo pipefail

# Create temp directory for extraction
SEND_TO_SLACK_TMP=$(mktemp -d)
trap 'rm -rf "$SEND_TO_SLACK_TMP"' EXIT

# Extract embedded files
HEADER

# Embed VERSION (ensure trailing newline before EOF marker)
echo "# VERSION" >> "$OUTPUT_FILE"
echo "cat > \"\$SEND_TO_SLACK_TMP/VERSION\" << 'EOF_VERSION'" >> "$OUTPUT_FILE"
cat "$ROOT_DIR/VERSION" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "EOF_VERSION" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Embed lib files
echo "mkdir -p \"\$SEND_TO_SLACK_TMP/lib/blocks\"" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

for file in "$ROOT_DIR"/lib/*.sh; do
    filename=$(basename "$file")
    echo "# lib/$filename" >> "$OUTPUT_FILE"
    echo "cat > \"\$SEND_TO_SLACK_TMP/lib/$filename\" << 'EOF_${filename^^}'" >> "$OUTPUT_FILE"
    cat "$file" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "EOF_${filename^^}" >> "$OUTPUT_FILE"
    echo "chmod +x \"\$SEND_TO_SLACK_TMP/lib/$filename\"" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
done

for file in "$ROOT_DIR"/lib/blocks/*.sh; do
    filename=$(basename "$file")
    echo "# lib/blocks/$filename" >> "$OUTPUT_FILE"
    echo "cat > \"\$SEND_TO_SLACK_TMP/lib/blocks/$filename\" << 'EOF_BLOCKS_${filename^^}'" >> "$OUTPUT_FILE"
    cat "$file" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "EOF_BLOCKS_${filename^^}" >> "$OUTPUT_FILE"
    echo "chmod +x \"\$SEND_TO_SLACK_TMP/lib/blocks/$filename\"" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
done

# Embed main script
echo "# bin/send-to-slack.sh" >> "$OUTPUT_FILE"
echo "cat > \"\$SEND_TO_SLACK_TMP/send-to-slack.sh\" << 'EOF_MAIN'" >> "$OUTPUT_FILE"
cat "$ROOT_DIR/bin/send-to-slack.sh" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "EOF_MAIN" >> "$OUTPUT_FILE"
echo "chmod +x \"\$SEND_TO_SLACK_TMP/send-to-slack.sh\"" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Add execution wrapper
cat >> "$OUTPUT_FILE" << 'FOOTER'
# Run the script
export SEND_TO_SLACK_ROOT="$SEND_TO_SLACK_TMP"
exec "$SEND_TO_SLACK_TMP/send-to-slack.sh" "$@"
FOOTER

chmod +x "$OUTPUT_FILE"

echo "Built: $OUTPUT_FILE"
echo "Size: $(wc -c < "$OUTPUT_FILE") bytes"
