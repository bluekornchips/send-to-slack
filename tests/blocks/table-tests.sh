#!/usr/bin/env bats
#
# Test file for blocks/table.sh
#

SMOKE_TEST=${SMOKE_TEST:-false}

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		echo "Failed to get git root" >&2
		exit 1
	fi

	SCRIPT="$GIT_ROOT/bin/blocks/table.sh"

	if [[ ! -f "$SCRIPT" ]]; then
		echo "Script not found: $SCRIPT" >&2
		exit 1
	fi

	export GIT_ROOT
	export SCRIPT
}

setup() {
	source "$SCRIPT"

	SEND_TO_SLACK_ROOT="$GIT_ROOT"

	export SEND_TO_SLACK_ROOT

	return 0
}

########################################################
# create_table
########################################################

@test "create_table:: handles no input" {
	run create_table <<<''
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "input is required"
}

@test "create_table:: handles invalid JSON" {
	run create_table <<<'invalid json'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "input must be valid JSON"
}

@test "create_table:: missing elements" {
	run create_table <<<'{"block_id": "test_id"}'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "rows field is required"
}

@test "create_table:: with rows" {
	run create_table <<<'{"rows": [[{"type": "raw_text", "text": "Hello, world!"}]]}'
	[[ "$status" -eq 0 ]]
	echo "$output" | jq '.rows[0][0].text == "Hello, world!"' >/dev/null
}

@test "create_table:: with block_id" {
	run create_table <<<'{"block_id": "test_id", "rows": [[{"type": "raw_text", "text": "test"}]]}'
	[[ "$status" -eq 0 ]]
	echo "$output" | jq '.block_id == "test_id"' >/dev/null
}

@test "create_table:: with column_settings" {
	run create_table <<<'{"column_settings": [{"align": "left"}], "rows": [[{"type": "raw_text", "text": "test"}]]}'
	[[ "$status" -eq 0 ]]
	echo "$output" | jq '.column_settings[0].align == "left"' >/dev/null
}

@test "create_table:: rows not array" {
	run create_table <<<'{"rows": "not an array"}'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "rows must be an array"
}

@test "create_table:: row not array" {
	run create_table <<<'{"rows": ["not an array"]}'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "row 0 must be an array"
}

@test "create_table:: cell missing type" {
	run create_table <<<'{"rows": [[{"text": "test"}]]}'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "cell \[0,0\] must have a type field"
}

@test "create_table:: invalid cell type" {
	run create_table <<<'{"rows": [[{"type": "invalid", "text": "test"}]]}'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "cell \[0,0\] type must be one of"
}

@test "create_table:: invalid column alignment" {
	run create_table <<<'{"column_settings": [{"align": "invalid"}], "rows": [[{"type": "raw_text", "text": "test"}]]}'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "align must be one of"
}

@test "create_table:: invalid column is_wrapped type" {
	run create_table <<<'{"column_settings": [{"is_wrapped": "not boolean"}], "rows": [[{"type": "raw_text", "text": "test"}]]}'
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "is_wrapped must be a boolean"
}

@test "create_table:: column_settings with left alignment" {
	local test_input
	test_input=$(jq -n '{
		column_settings: [{align: "left"}],
		rows: [[{type: "raw_text", text: "Left aligned"}]]
	}')

	run create_table <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.column_settings[0].align == "left"' >/dev/null
}

@test "create_table:: column_settings with center alignment" {
	local test_input
	test_input=$(jq -n '{
		column_settings: [{align: "center"}],
		rows: [[{type: "raw_text", text: "Center aligned"}]]
	}')

	run create_table <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.column_settings[0].align == "center"' >/dev/null
}

@test "create_table:: column_settings with right alignment" {
	local test_input
	test_input=$(jq -n '{
		column_settings: [{align: "right"}],
		rows: [[{type: "raw_text", text: "Right aligned"}]]
	}')

	run create_table <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.column_settings[0].align == "right"' >/dev/null
}

@test "create_table:: column_settings with is_wrapped true" {
	local test_input
	test_input=$(jq -n '{
		column_settings: [{is_wrapped: true}],
		rows: [[{type: "raw_text", text: "Wrapped text"}]]
	}')

	run create_table <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.column_settings[0].is_wrapped == true' >/dev/null
}

@test "create_table:: column_settings with is_wrapped false" {
	local test_input
	test_input=$(jq -n '{
		column_settings: [{is_wrapped: false}],
		rows: [[{type: "raw_text", text: "Not wrapped"}]]
	}')

	run create_table <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.column_settings[0].is_wrapped == false' >/dev/null
}

@test "create_table:: rich_text cell with link" {
	local test_input
	test_input=$(jq -n '{
		rows: [[{
			type: "rich_text",
			elements: [{
				type: "rich_text_section",
				elements: [{
					type: "link",
					url: "https://slack.com",
					text: "Slack"
				}]
			}]
		}]]
	}')

	run create_table <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.rows[0][0].type == "rich_text"' >/dev/null
	echo "$output" | jq -e '.rows[0][0].elements[0].elements[0].type == "link"' >/dev/null
	echo "$output" | jq -e '.rows[0][0].elements[0].elements[0].url == "https://slack.com"' >/dev/null
}

@test "create_table:: rich_text cell with styled text" {
	local test_input
	test_input=$(jq -n '{
		rows: [[{
			type: "rich_text",
			elements: [{
				type: "rich_text_section",
				elements: [{
					type: "text",
					text: "Bold text",
					style: {bold: true}
				}]
			}]
		}]]
	}')

	run create_table <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.rows[0][0].type == "rich_text"' >/dev/null
	echo "$output" | jq -e '.rows[0][0].elements[0].elements[0].style.bold == true' >/dev/null
}

@test "create_table:: multiple rows with mixed cell types" {
	local test_input
	test_input=$(jq -n '{
		rows: [
			[
				{type: "raw_text", text: "Header 1"},
				{type: "raw_text", text: "Header 2"}
			],
			[
				{type: "raw_text", text: "Data 1"},
				{
					type: "rich_text",
					elements: [{
						type: "rich_text_section",
						elements: [{type: "text", text: "Rich data"}]
					}]
				}
			]
		]
	}')

	run create_table <<<"$test_input"
	[[ "$status" -eq 0 ]]
	echo "$output" | jq -e '.rows | length == 2' >/dev/null
	echo "$output" | jq -e '.rows[0][0].type == "raw_text"' >/dev/null
	echo "$output" | jq -e '.rows[1][1].type == "rich_text"' >/dev/null
}

@test "create_table:: validates max rows limit" {
	local many_rows
	many_rows=$(jq -n '[range(101) | [{type: "raw_text", text: "Row"}]]')

	run create_table <<<"$(jq -n --argjson rows "$many_rows" '{rows: $rows}')"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "rows cannot exceed 100 entries"
}

@test "create_table:: validates max columns limit" {
	local many_cols
	many_cols=$(jq -n '[range(21) | {type: "raw_text", text: "Col"}]')

	run create_table <<<"$(jq -n --argjson cols "$many_cols" '{rows: [$cols]}')"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "row 0 cannot exceed 20 cells"
}

@test "create_table:: validates max column_settings limit" {
	local many_settings
	many_settings=$(jq -n '[range(21) | {align: "left"}]')
	local rows_json
	rows_json=$(jq -n '[[{type: "raw_text", text: "test"}]]')

	run create_table <<<"$(jq -n --argjson settings "$many_settings" --argjson rows "$rows_json" '{column_settings: $settings, rows: $rows}')"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "column_settings cannot exceed 20 entries"
}
