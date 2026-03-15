#!/usr/bin/env bats
#
# Tests for lib/create-blocks.sh
#

setup_file() {
	GIT_ROOT="$(git rev-parse --show-toplevel || echo "")"
	if [[ -z "$GIT_ROOT" ]]; then
		fail "setup_file:: Failed to get git root"
	fi

	SCRIPT="$GIT_ROOT/lib/create-blocks.sh"
	if [[ ! -f "$SCRIPT" ]]; then
		fail "setup_file:: Script not found: $SCRIPT"
	fi

	RICH_TEXT_EXAMPLES_FILE="$GIT_ROOT/examples/rich-text.yaml"
	BLOCK_FIXTURES_DIR="$GIT_ROOT/examples/fixtures"

	export GIT_ROOT
	export SCRIPT
	export RICH_TEXT_EXAMPLES_FILE
	export BLOCK_FIXTURES_DIR

	return 0
}

setup() {
	source "$SCRIPT"

	_SLACK_WORKSPACE=$(mktemp -d "${BATS_TEST_TMPDIR}/create-blocks-tests.workspace.XXXXXX")
	export _SLACK_WORKSPACE

	CREATE_BLOCK_OUTPUT_FILE=$(mktemp "$_SLACK_WORKSPACE/block-out.XXXXXX")
	export CREATE_BLOCK_OUTPUT_FILE

	return 0
}

teardown() {
	rm -rf "$_SLACK_WORKSPACE"

	return 0
}

########################################################
# Helpers
########################################################

block_output_json() { cat "$CREATE_BLOCK_OUTPUT_FILE"; }

########################################################
# create_block
########################################################

@test "create_block:: no input" {
	run create_block
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "input is required"
}

@test "create_block:: invalid JSON" {
	run create_block "invalid json"
	[[ "$status" -eq 1 ]]
	echo "$output" | grep -q "must be valid JSON"
}

@test "create_block:: unsupported block type" {
	local block
	block=$(jq -n '{"type": "unsupported"}')

	run create_block "$block"
	[[ "$status" -eq 0 ]]
	echo "$output" | grep -q "unsupported block type"
}

@test "create_block:: rich-text-section-with-all-elements" {
	local block_type block_value
	block_type=$(yq -r '.jobs[] | select(.name == "rich-text-section-with-all-elements") | .plan[0].params.blocks[0] | keys[0]' "$RICH_TEXT_EXAMPLES_FILE")
	block_value=$(yq -o json -r '.jobs[] | select(.name == "rich-text-section-with-all-elements") | .plan[0].params.blocks[0].'"$block_type" "$RICH_TEXT_EXAMPLES_FILE")

	run create_block "$block_value" "$block_type"
	[[ "$status" -eq 0 ]]
}

@test "create_block:: rich-text-attachment-with-color" {
	local block_type block_value
	block_type=$(yq -r '.jobs[] | select(.name == "rich-text-attachment-with-color") | .plan[0].params.blocks[0] | keys[0]' "$RICH_TEXT_EXAMPLES_FILE")
	block_value=$(yq -o json -r '.jobs[] | select(.name == "rich-text-attachment-with-color") | .plan[0].params.blocks[0].'"$block_type" "$RICH_TEXT_EXAMPLES_FILE")

	run create_block "$block_value" "$block_type"
	[[ "$status" -eq 0 ]]
}

@test "create_block:: rich-text-lists-with-all-options" {
	local block_type block_value
	block_type=$(yq -r '.jobs[] | select(.name == "rich-text-lists-with-all-options") | .plan[0].params.blocks[0] | keys[0]' "$RICH_TEXT_EXAMPLES_FILE")
	block_value=$(yq -o json -r '.jobs[] | select(.name == "rich-text-lists-with-all-options") | .plan[0].params.blocks[0].'"$block_type" "$RICH_TEXT_EXAMPLES_FILE")

	run create_block "$block_value" "$block_type"
	[[ "$status" -eq 0 ]]
}

@test "create_block:: multiple-rich-text-blocks" {
	local block_type block_value
	block_type=$(yq -r '.jobs[] | select(.name == "multiple-rich-text-blocks") | .plan[0].params.blocks[0] | keys[0]' "$RICH_TEXT_EXAMPLES_FILE")
	block_value=$(yq -o json -r '.jobs[] | select(.name == "multiple-rich-text-blocks") | .plan[0].params.blocks[0].'"$block_type" "$RICH_TEXT_EXAMPLES_FILE")

	run create_block "$block_value" "$block_type"
	[[ "$status" -eq 0 ]]
}

@test "create_block:: rich-text-preformatted-and-quote" {
	local block_type block_value
	block_type=$(yq -r '.jobs[] | select(.name == "rich-text-preformatted-and-quote") | .plan[0].params.blocks[0] | keys[0]' "$RICH_TEXT_EXAMPLES_FILE")
	block_value=$(yq -o json -r '.jobs[] | select(.name == "rich-text-preformatted-and-quote") | .plan[0].params.blocks[0].'"$block_type" "$RICH_TEXT_EXAMPLES_FILE")

	run create_block "$block_value" "$block_type"
	[[ "$status" -eq 0 ]]
}

@test "create_block:: interpolates environment variables in block JSON" {
	export BUILD_ID="12345"
	export BUILD_NAME="42"
	export BUILD_JOB_NAME="test-job"
	export BUILD_PIPELINE_NAME="test-pipeline"
	export BUILD_TEAM_NAME="main"
	export BUILD_CREATED_BY="test-user"
	export BUILD_PIPELINE_INSTANCE_VARS="{}"
	export ATC_EXTERNAL_URL="https://concourse.example.com"

	local block_input
	block_input=$(jq -n '{
		type: "text",
		text: {
			type: "mrkdwn",
			text: "Build ID: $BUILD_ID, Build Name: $BUILD_NAME"
		}
	}')

	run create_block "$block_input" "section"
	[[ "$status" -eq 0 ]]

	block_output_json | jq -e '.text.text | contains("12345")' >/dev/null
	block_output_json | jq -e '.text.text | contains("42")' >/dev/null
	block_output_json | jq -e '.text.text | contains("$BUILD_ID") == false' >/dev/null
	block_output_json | jq -e '.text.text | contains("$BUILD_NAME") == false' >/dev/null

	unset BUILD_ID BUILD_NAME BUILD_JOB_NAME BUILD_PIPELINE_NAME BUILD_TEAM_NAME BUILD_CREATED_BY BUILD_PIPELINE_INSTANCE_VARS ATC_EXTERNAL_URL
}

@test "create_block:: interpolates all Concourse metadata variables" {
	export BUILD_ID="67890"
	export BUILD_NAME="99"
	export BUILD_JOB_NAME="metadata-job"
	export BUILD_PIPELINE_NAME="metadata-pipeline"
	export BUILD_TEAM_NAME="test-team"
	export BUILD_CREATED_BY="ci-user"
	export BUILD_PIPELINE_INSTANCE_VARS='{"env":"prod"}'
	export ATC_EXTERNAL_URL="https://ci.example.com"

	local block_input
	block_input=$(jq -n '{
		type: "fields",
		fields: [
			{type: "mrkdwn", text: "*BUILD_ID:*\n`$BUILD_ID`"},
			{type: "mrkdwn", text: "*BUILD_NAME:*\n`$BUILD_NAME`"},
			{type: "mrkdwn", text: "*BUILD_JOB_NAME:*\n`$BUILD_JOB_NAME`"},
			{type: "mrkdwn", text: "*BUILD_PIPELINE_NAME:*\n`$BUILD_PIPELINE_NAME`"},
			{type: "mrkdwn", text: "*BUILD_TEAM_NAME:*\n`$BUILD_TEAM_NAME`"},
			{type: "mrkdwn", text: "*BUILD_CREATED_BY:*\n`$BUILD_CREATED_BY`"},
			{type: "mrkdwn", text: "*BUILD_PIPELINE_INSTANCE_VARS:*\n`$BUILD_PIPELINE_INSTANCE_VARS`"},
			{type: "mrkdwn", text: "*ATC_EXTERNAL_URL:*\n<$ATC_EXTERNAL_URL|$ATC_EXTERNAL_URL>"}
		]
	}')

	run create_block "$block_input" "section"
	[[ "$status" -eq 0 ]]

	block_output_json | jq -e '.fields[0].text | contains("67890")' >/dev/null
	block_output_json | jq -e '.fields[1].text | contains("99")' >/dev/null
	block_output_json | jq -e '.fields[2].text | contains("metadata-job")' >/dev/null
	block_output_json | jq -e '.fields[3].text | contains("metadata-pipeline")' >/dev/null
	block_output_json | jq -e '.fields[4].text | contains("test-team")' >/dev/null
	block_output_json | jq -e '.fields[5].text | contains("ci-user")' >/dev/null
	block_output_json | jq -e '.fields[6].text | contains("prod")' >/dev/null
	block_output_json | jq -e '.fields[7].text | contains("https://ci.example.com")' >/dev/null

	block_output_json | jq -e '.fields[0].text | contains("$BUILD_ID") == false' >/dev/null
	block_output_json | jq -e '.fields[7].text | contains("$ATC_EXTERNAL_URL") == false' >/dev/null

	unset BUILD_ID BUILD_NAME BUILD_JOB_NAME BUILD_PIPELINE_NAME BUILD_TEAM_NAME BUILD_CREATED_BY BUILD_PIPELINE_INSTANCE_VARS ATC_EXTERNAL_URL
}

@test "create_block:: handles missing environment variables gracefully" {
	unset BUILD_ID BUILD_NAME 2>/dev/null || true

	local block_input
	block_input=$(jq -n '{
		type: "text",
		text: {
			type: "mrkdwn",
			text: "Build ID: $BUILD_ID"
		}
	}')

	run create_block "$block_input" "section"
	[[ "$status" -eq 0 ]]

	# Missing variables should be replaced with empty string by envsubst
	block_output_json | jq -e '.text.text | contains("Build ID: ")' >/dev/null
}

@test "create_block:: interpolates variables in nested JSON structures" {
	export TEST_VAR="nested-value"

	local block_input
	block_input=$(jq -n '{
		elements: [
			{
				type: "rich_text_section",
				elements: [
					{type: "text", text: "Value: $TEST_VAR"}
				]
			}
		]
	}')

	run create_block "$block_input" "rich-text"
	[[ "$status" -eq 0 ]]

	block_output_json | jq -e '.elements[0].elements[0].text | contains("nested-value")' >/dev/null
	block_output_json | jq -e '.elements[0].elements[0].text | contains("$TEST_VAR") == false' >/dev/null

	unset TEST_VAR
}

@test "create_block:: preserves JSON structure after interpolation" {
	export BUILD_ID="12345"

	local block_input
	block_input=$(jq -n '{
		type: "fields",
		fields: [
			{type: "mrkdwn", text: "ID: $BUILD_ID"},
			{type: "plain_text", text: "Static text"}
		],
		block_id: "test-block"
	}')

	run create_block "$block_input" "section"
	[[ "$status" -eq 0 ]]

	block_output_json | jq -e '.type == "section"' >/dev/null
	block_output_json | jq -e '.block_id == "test-block"' >/dev/null
	block_output_json | jq -e '.fields | length == 2' >/dev/null
	block_output_json | jq -e '.fields[0].type == "mrkdwn"' >/dev/null
	block_output_json | jq -e '.fields[1].type == "plain_text"' >/dev/null
	block_output_json | jq -e '.fields[1].text == "Static text"' >/dev/null

	unset BUILD_ID
}

@test "create_block:: handles variables with special characters" {
	export SPECIAL_VAR="value with spaces and special chars: !@#$%"

	local block_input
	block_input=$(jq -n '{
		type: "text",
		text: {
			type: "mrkdwn",
			text: "Special: $SPECIAL_VAR"
		}
	}')

	run create_block "$block_input" "section"
	[[ "$status" -eq 0 ]]

	block_output_json | jq -e '.text.text | contains("value with spaces")' >/dev/null

	unset SPECIAL_VAR
}

@test "create_block:: interpolates variables in rich-text block" {
	export BUILD_ID="99999"
	export BUILD_NAME="100"

	local block_input
	block_input=$(jq -n '{
		elements: [
			{
				type: "rich_text_section",
				elements: [
					{type: "text", text: "Build $BUILD_ID"},
					{type: "text", text: " Name $BUILD_NAME"}
				]
			}
		]
	}')

	run create_block "$block_input" "rich-text"
	[[ "$status" -eq 0 ]]

	block_output_json | jq -e '.elements[0].elements[0].text | contains("99999")' >/dev/null
	block_output_json | jq -e '.elements[0].elements[1].text | contains("100")' >/dev/null

	unset BUILD_ID BUILD_NAME
}
