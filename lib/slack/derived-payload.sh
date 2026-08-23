#!/usr/bin/env bash
#
# Shared builder for Concourse-shaped {source, params} input payloads
#

# Write a derived Concourse-style input payload to a temp file
#
# Arguments:
#   $1 - source_json: JSON object for the source field
#   $2 - params_json: JSON object for the params field
#   $3 - name_prefix: mktemp name prefix under _SLACK_WORKSPACE
#
# Outputs:
#   Absolute path to the new payload file on stdout
#
# Returns:
#   0 on success
#   1 on failure
_build_derived_input_payload() {
	local source_json="$1"
	local params_json="$2"
	local name_prefix="${3:-derived}"

	if [[ -z "${_SLACK_WORKSPACE:-}" ]] || [[ ! -d "${_SLACK_WORKSPACE}" ]]; then
		echo "_build_derived_input_payload:: _SLACK_WORKSPACE must be a directory" >&2
		return 1
	fi

	local source_file params_file payload_file
	if ! source_file=$(mktemp "${_SLACK_WORKSPACE}/${name_prefix}.source.XXXXXX"); then
		echo "_build_derived_input_payload:: mktemp failed for source file" >&2
		return 1
	fi

	if ! params_file=$(mktemp "${_SLACK_WORKSPACE}/${name_prefix}.params.XXXXXX"); then
		echo "_build_derived_input_payload:: mktemp failed for params file" >&2
		rm -f "${source_file}"
		return 1
	fi

	if ! payload_file=$(mktemp "${_SLACK_WORKSPACE}/${name_prefix}.payload.XXXXXX"); then
		echo "_build_derived_input_payload:: mktemp failed for payload file" >&2
		rm -f "${source_file}" "${params_file}"
		return 1
	fi

	if ! chmod 0600 "${source_file}" "${params_file}" "${payload_file}"; then
		echo "_build_derived_input_payload:: failed to secure temp files" >&2
		rm -f "${source_file}" "${params_file}" "${payload_file}"
		return 1
	fi

	printf '%s' "$source_json" >"${source_file}"
	printf '%s' "$params_json" >"${params_file}"

	if ! jq -n \
		--slurpfile source "${source_file}" \
		--slurpfile params "${params_file}" \
		'{
			"source": $source[0],
			"params": $params[0]
		}' >"${payload_file}"; then

		echo "_build_derived_input_payload:: jq failed to build payload" >&2

		rm -f "${source_file}" "${params_file}" "${payload_file}"

		return 1
	fi

	rm -f "${source_file}" "${params_file}"

	printf '%s\n' "${payload_file}"

	return 0
}
