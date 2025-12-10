#!/usr/bin/env bash
#
# Table Block implementation following Slack Block Kit guidelines
# Ref: https://docs.slack.dev/reference/block-kit/blocks/table-block/
#
set -eo pipefail
umask 077

# Constants
BLOCK_TYPE="table"
MAX_ROWS=100
MAX_COLS=20
MAX_COLUMN_SETTINGS=20
SUPPORTED_CELL_TYPES=("raw_text" "rich_text")
SUPPORTED_ALIGNMENTS=("left" "center" "right")

# Process table block and create Slack Block Kit table block format.
#
# Inputs:
# - Reads JSON from stdin with table configuration
#
# Side Effects:
# - Outputs Slack Block Kit table block JSON to stdout
#
# Returns:
# - 0 on successful table block creation with valid rows and cells
# - 1 if input is empty, invalid JSON, missing rows, or validation fails
create_table() {
	local input
	input=$(cat)

	if [[ -z "${input}" ]]; then
		echo "create_table:: input is required" >&2
		return 1
	fi

	local input_json
	input_json=$(mktemp /tmp/send-to-slack-XXXXXX)
	if ! chmod 700 "$input_json"; then
		echo "create_table:: failed to secure temp file ${input_json}" >&2
		rm -f "$input_json"
		return 1
	fi
	trap 'rm -f "$input_json"' RETURN EXIT
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

	local block
	local input_rows

	input_rows=$(jq '.rows' "$input_json")

	block=$(jq -n \
		--arg block_type "$BLOCK_TYPE" \
		--argjson input_rows "$input_rows" \
		'{ type: $block_type, rows: $input_rows }')

	# Add optional block_id if present
	if jq -e '.block_id' "$input_json" >/dev/null 2>&1; then
		local block_id
		block_id=$(jq -r '.block_id' "$input_json")
		block=$(jq --arg block_id "$block_id" '. + {block_id: $block_id}' <<<"$block")
	fi

	# Add optional column_settings if present
	if jq -e '.column_settings' "$input_json" >/dev/null 2>&1; then
		local column_settings_json
		column_settings_json=$(jq '.column_settings' "$input_json")
		block=$(jq --argjson column_settings "$column_settings_json" '. + {column_settings: $column_settings}' <<<"$block")
	fi

	echo "$block"

	return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	create_table "$@"
fi
