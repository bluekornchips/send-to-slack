#!/usr/bin/env bash
#
# Table Block implementation following Slack Block Kit guidelines
# Ref: https://docs.slack.dev/reference/block-kit/blocks/table-block/
#

# Constants
BLOCK_TYPE="table"
MAX_ROWS=100
MAX_COLS=20
MAX_COLUMN_SETTINGS=20
TABLE_MAX_CHAR_COUNT=10000
SUPPORTED_CELL_TYPES=("raw_text" "rich_text")
SUPPORTED_ALIGNMENTS=("left" "center" "right")

# Process table block and create Slack Block Kit table block format.
#
# Inputs:
# - Reads JSON from stdin with table configuration
# - TABLE_BLOCK_OUTPUT_FILE (required): path where block JSON will be written
#
# Side Effects:
# - Writes block JSON to the path in TABLE_BLOCK_OUTPUT_FILE (required)
# - When total cell character count exceeds TABLE_MAX_CHAR_COUNT, writes a
#   two-element JSON array instead: a context block and a file block pointing
#   to a plain-text rendering of the table in _SLACK_WORKSPACE
#
# Returns:
# - 0 on successful table block creation with valid rows and cells
# - 1 if TABLE_BLOCK_OUTPUT_FILE unset, input empty, invalid JSON, missing rows, or validation fails
create_table() {
	if [[ -z "${TABLE_BLOCK_OUTPUT_FILE:-}" ]]; then
		echo "create_table:: TABLE_BLOCK_OUTPUT_FILE is required" >&2
		return 1
	fi

	local input
	input=$(cat)

	if [[ -z "${input}" ]]; then
		echo "create_table:: input is required" >&2
		return 1
	fi

	local input_json
	input_json=$(mktemp "$_SLACK_WORKSPACE/table.input-json.XXXXXX")
	echo "$input" >"$input_json"

	if ! jq . "$input_json" >/dev/null 2>&1; then
		echo "create_table:: input must be valid JSON" >&2
		return 1
	fi

	# Validate required fields
	if ! jq -e '.rows' "$input_json" >/dev/null 2>&1; then
		echo "create_table:: rows field is required" >&2
		return 1
	fi

	if ! jq -e '.rows | type == "array"' "$input_json" >/dev/null 2>&1; then
		echo "create_table:: rows must be an array" >&2
		return 1
	fi

	# Validate rows length (max 100)
	local rows_length
	rows_length=$(jq -r '.rows | length' "$input_json")
	if ((rows_length > MAX_ROWS)); then
		echo "create_table:: rows cannot exceed $MAX_ROWS entries" >&2
		return 1
	fi

	# Validate each row
	for ((i = 0; i < rows_length; i++)); do
		local row_path=".rows[$i]"

		# Row must be an array
		if ! jq -e "$row_path | type == \"array\"" "$input_json" >/dev/null 2>&1; then
			echo "create_table:: row $i must be an array" >&2
			return 1
		fi

		# Row cannot exceed $MAX_COLS cells
		local row_length
		row_length=$(jq -r "$row_path | length" "$input_json")
		if ((row_length > MAX_COLS)); then
			echo "create_table:: row $i cannot exceed $MAX_COLS cells" >&2
			return 1
		fi

		# Validate each cell in the row
		for ((j = 0; j < row_length; j++)); do
			local cell_path="${row_path}[$j]"

			# Cell must have type field
			if ! jq -e "$cell_path.type" "$input_json" >/dev/null 2>&1; then
				echo "create_table:: cell [$i,$j] must have a type field" >&2
				return 1
			fi

			# Cell type must be one of the supported types
			local cell_type
			cell_type=$(jq -r "$cell_path.type" "$input_json")
			if ! [[ " ${SUPPORTED_CELL_TYPES[*]} " =~ ${cell_type} ]]; then
				echo "create_table:: cell [$i,$j] type must be one of: ${SUPPORTED_CELL_TYPES[*]}, got: $cell_type" >&2
				return 1
			fi
		done
	done

	# Validate column_settings if present
	if jq -e '.column_settings' "$input_json" >/dev/null 2>&1; then
		# Must be an array
		if ! jq -e '.column_settings | type == "array"' "$input_json" >/dev/null 2>&1; then
			echo "create_table:: column_settings must be an array" >&2
			return 1
		fi

		# Cannot exceed $MAX_COLUMN_SETTINGS entries
		local column_settings_length
		column_settings_length=$(jq -r '.column_settings | length' "$input_json")
		if ((column_settings_length > MAX_COLUMN_SETTINGS)); then
			echo "create_table:: column_settings cannot exceed $MAX_COLUMN_SETTINGS entries" >&2
			return 1
		fi

		# Validate each column setting
		for ((i = 0; i < column_settings_length; i++)); do
			local setting_path=".column_settings[$i]"

			# Check align if present
			if jq -e "$setting_path.align" "$input_json" >/dev/null 2>&1; then
				local align_value
				align_value=$(jq -r "$setting_path.align" "$input_json")
				if ! [[ " ${SUPPORTED_ALIGNMENTS[*]} " =~ ${align_value} ]]; then
					echo "create_table:: column_settings[$i].align must be one of: ${SUPPORTED_ALIGNMENTS[*]}, got: $align_value" >&2
					return 1
				fi
			fi

			# Check is_wrapped if present - must be boolean
			if jq -e "$setting_path.is_wrapped" "$input_json" >/dev/null 2>&1; then
				if ! jq -e "$setting_path.is_wrapped | type == \"boolean\"" "$input_json" >/dev/null 2>&1; then
					echo "create_table:: column_settings[$i].is_wrapped must be a boolean" >&2
					return 1
				fi
			fi
		done
	fi

	# Check total character count across all cells; fall back to file attachment if over limit.
	# For raw_text cells, count .text length.
	# For rich_text cells, sum all nested .text leaf string lengths.
	local total_chars
	total_chars=$(jq '
		[.rows[][] |
			if .type == "raw_text" then (.text | length)
			elif .type == "rich_text" then ([.. | .text? | strings | length] | add // 0)
			else 0 end
		] | add // 0
	' "$input_json")

	if ((total_chars > TABLE_MAX_CHAR_COUNT)); then
		if ! _table_overflow_to_file "$input_json" "$total_chars"; then
			return 1
		fi

		return 0
	fi

	# Build block via temp files so large JSON is never on the command line (avoids ARG_MAX).
	local block_file
	local tmp_file
	block_file=$(mktemp "$_SLACK_WORKSPACE/table.block.XXXXXX")
	tmp_file=$(mktemp "$_SLACK_WORKSPACE/table.block.XXXXXX")

	jq -n \
		--arg block_type "$BLOCK_TYPE" \
		--slurpfile input_rows <(jq '.rows' "$input_json") \
		'{ type: $block_type, rows: $input_rows[0] }' \
		>"$block_file"

	# Add optional block_id if present
	if jq -e '.block_id' "$input_json" >/dev/null 2>&1; then
		local block_id
		block_id=$(jq -r '.block_id' "$input_json")
		jq --arg block_id "$block_id" '. + {block_id: $block_id}' "$block_file" >"$tmp_file" && mv "$tmp_file" "$block_file"
	fi

	# Add optional column_settings if present
	if jq -e '.column_settings' "$input_json" >/dev/null 2>&1; then
		jq --slurpfile column_settings <(jq '.column_settings' "$input_json") '. + {column_settings: $column_settings[0]}' "$block_file" >"$tmp_file" && mv "$tmp_file" "$block_file"
	fi

	cp "$block_file" "$TABLE_BLOCK_OUTPUT_FILE"

	return 0
}

# Handle table overflow by writing raw JSON to a file and emitting a two-element
# JSON array containing a context block and a file block to TABLE_BLOCK_OUTPUT_FILE.
#
# Inputs:
# - $1 - input_json_file: path to validated table input JSON file
# - $2 - total_chars: total character count across all cells
#
# Side Effects:
# - Writes a .json file to _SLACK_WORKSPACE
# - Writes a JSON array to TABLE_BLOCK_OUTPUT_FILE
#
# Returns:
# - 0 on success
# - 1 on failure
_table_overflow_to_file() {
	local input_json_file="$1"
	local total_chars="$2"

	local row_count
	local col_count
	row_count=$(jq '.rows | length' "$input_json_file")
	col_count=$(jq '.rows[0] | length' "$input_json_file")

	echo "create_table:: table exceeds ${TABLE_MAX_CHAR_COUNT} char limit" \
		"(${total_chars} chars, ${row_count}x${col_count} cells)," \
		"falling back to file attachment" >&2

	local json_file
	json_file=$(mktemp "$_SLACK_WORKSPACE/table.overflow.XXXXXX.json")
	cp "$input_json_file" "$json_file"

	local context_block
	context_block=$(jq -n \
		--arg msg "Table too large for inline display (${total_chars} chars, limit ${TABLE_MAX_CHAR_COUNT}). Attached as JSON." \
		'{
			type: "context",
			elements: [{ type: "plain_text", text: $msg }]
		}')

	local file_block
	file_block=$(jq -n \
		--arg path "$json_file" \
		--arg title "table-${row_count}x${col_count}.json" \
		'{ file: { path: $path, title: $title } }')

	jq -n \
		--argjson context "$context_block" \
		--argjson file "$file_block" \
		'[$context, $file]' >"$TABLE_BLOCK_OUTPUT_FILE"

	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	set -eo pipefail
	umask 077
	create_table "$@"
	exit $?
fi
