#!/usr/bin/env bash
#
# S3 to Slack integration script
# Downloads files from S3 and uploads them to Slack
# Can also generate pre-signed URLs for direct linking
#
set -eo pipefail

########################################################
# Constants
########################################################
MODE_UPLOAD="upload"
MODE_LINK="link"
MODE_IMAGE="image"

# Display usage information
#
# Side Effects:
# - Outputs usage to stderr
usage() {
	cat >&2 <<-EOF
		Usage: s3-to-slack.sh [OPTIONS] <bucket> <key> <channel>
		
		Downloads S3 content and shares it in Slack.
		
		Required Arguments:
		  bucket    S3 bucket name
		  key       S3 object key (path)
		  channel   Slack channel name or ID
		
		Options:
		  -m, --mode MODE      Operation mode: upload, link, or image (default: upload)
		                        upload: Download and upload file to Slack
		                        link:   Generate pre-signed URL and create link block
		                        image:  Generate pre-signed URL for image block
		  -t, --title TITLE     Title for uploaded file (default: filename)
		  -e, --expire HOURS    Pre-signed URL expiration in hours (default: 24)
		  -h, --help           Show this help message
		
		Environment Variables:
		  SLACK_BOT_USER_OAUTH_TOKEN  Slack bot OAuth token (required)
		  AWS_REGION                  AWS region (default: us-east-1)
		
		Examples:
		  # Upload file to Slack
		  s3-to-slack.sh my-bucket reports/report.pdf notifications
		
		  # Create link block with pre-signed URL
		  s3-to-slack.sh -m link my-bucket reports/report.pdf notifications
		
		  # Display image from S3
		  s3-to-slack.sh -m image my-bucket images/chart.png notifications
	EOF
}

# Validate required dependencies
#
# Returns:
#   0 if all dependencies are available
#   1 if any dependency is missing
check_dependencies() {
	local missing_deps=()
	local required_commands=("jq" "curl" "aws")

	for cmd in "${required_commands[@]}"; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			missing_deps+=("$cmd")
		fi
	done

	if [[ ${#missing_deps[@]} -gt 0 ]]; then
		echo "check_dependencies:: missing required dependencies: ${missing_deps[*]}" >&2
		echo "check_dependencies:: please install missing dependencies and try again" >&2
		return 1
	fi

	return 0
}

# Generate pre-signed URL for S3 object
#
# Arguments:
#   $1 - bucket: S3 bucket name
#   $2 - key: S3 object key
#   $3 - expiration_hours: URL expiration in hours
#
# Side Effects:
#   Outputs pre-signed URL to stdout
#
# Returns:
#   0 on success
#   1 on failure
generate_presigned_url() {
	local bucket="$1"
	local key="$2"
	local expiration_hours="${3:-24}"
	local expiration_seconds=$((expiration_hours * 3600))

	if [[ -z "$bucket" ]] || [[ -z "$key" ]]; then
		echo "generate_presigned_url:: bucket and key are required" >&2
		return 1
	fi

	local url
	if ! url=$(aws s3 presign "s3://${bucket}/${key}" --expires-in "$expiration_seconds" 2>&1); then
		echo "generate_presigned_url:: failed to generate pre-signed URL: $url" >&2
		return 1
	fi

	echo "$url"
	return 0
}

# Create Slack link block with S3 pre-signed URL
#
# Arguments:
#   $1 - url: Pre-signed URL
#   $2 - display_text: Text to display in Slack
#
# Side Effects:
#   Outputs Slack block JSON to stdout
create_link_block() {
	local url="$1"
	local display_text="$2"

	if [[ -z "$url" ]]; then
		echo "create_link_block:: URL is required" >&2
		return 1
	fi

	local block
	block=$(jq -n \
		--arg url "$url" \
		--arg text "${display_text:-File}" \
		'{
			type: "section",
			text: {
				type: "mrkdwn",
				text: "📎 <\($url)|\($text)>"
			}
		}')

	echo "$block"
	return 0
}

# Create Slack image block with S3 pre-signed URL
#
# Arguments:
#   $1 - url: Pre-signed URL
#   $2 - alt_text: Alt text for image
#
# Side Effects:
#   Outputs Slack block JSON to stdout
create_image_block() {
	local url="$1"
	local alt_text="$2"

	if [[ -z "$url" ]]; then
		echo "create_image_block:: URL is required" >&2
		return 1
	fi

	local block
	block=$(jq -n \
		--arg url "$url" \
		--arg alt "${alt_text:-Image}" \
		'{
			type: "image",
			image_url: $url,
			alt_text: $alt
		}')

	echo "$block"
	return 0
}

# Download from S3 and upload to Slack
#
# Arguments:
#   $1 - bucket: S3 bucket name
#   $2 - key: S3 object key
#   $3 - channel: Slack channel
#   $4 - title: File title (optional)
#
# Side Effects:
#   Uploads file to Slack and outputs file metadata
#
# Returns:
#   0 on success
#   1 on failure
upload_s3_to_slack() {
	local bucket="$1"
	local key="$2"
	local channel="$3"
	local title="${4:-${key##*/}}"

	if [[ -z "$bucket" ]] || [[ -z "$key" ]] || [[ -z "$channel" ]]; then
		echo "upload_s3_to_slack:: bucket, key, and channel are required" >&2
		return 1
	fi

	if [[ -z "${SLACK_BOT_USER_OAUTH_TOKEN}" ]]; then
		echo "upload_s3_to_slack:: SLACK_BOT_USER_OAUTH_TOKEN environment variable is required" >&2
		return 1
	fi

	# Download from S3 to temp file
	local tmp_file
	tmp_file=$(mktemp /tmp/s3-slack-XXXXXX)
	trap 'rm -f "$tmp_file"' RETURN EXIT

	echo "Downloading s3://${bucket}/${key}..." >&2
	if ! aws s3 cp "s3://${bucket}/${key}" "$tmp_file" >&2; then
		echo "upload_s3_to_slack:: failed to download from S3" >&2
		return 1
	fi

	local filename="${key##*/}"
	local file_size
	file_size=$(stat -c%s "$tmp_file" 2>/dev/null || stat -f%z "$tmp_file" 2>/dev/null)

	echo "Uploading ${filename} (${file_size} bytes) to Slack..." >&2

	# Use existing file upload functionality
	export CHANNEL="$channel"
	export SLACK_BOT_USER_OAUTH_TOKEN="${SLACK_BOT_USER_OAUTH_TOKEN}"

	local file_config
	file_config=$(jq -n \
		--arg path "$tmp_file" \
		--arg title "$title" \
		'{
			file: {
				path: $path,
				title: $title
			}
		}')

	# Source the file-upload script if available, otherwise use direct API call
	if [[ -f "$(dirname "$0")/file-upload.sh" ]]; then
		echo "$file_config" | "$(dirname "$0")/file-upload.sh"
	else
		# Fallback: direct Slack API call
		local api_response
		api_response=$(curl -s -X POST \
			-H "Authorization: Bearer ${SLACK_BOT_USER_OAUTH_TOKEN}" \
			-F "channels=${channel}" \
			-F "title=${title}" \
			-F "file=@${tmp_file}" \
			"https://slack.com/api/files.upload")

		if ! jq -e '.ok' <<<"$api_response" >/dev/null 2>&1; then
			echo "upload_s3_to_slack:: Slack API error:" >&2
			echo "$api_response" | jq . >&2
			return 1
		fi

		echo "$api_response" | jq '.file'
	fi

	return 0
}

# Main function
main() {
	local mode="$MODE_UPLOAD"
	local title=""
	local expiration_hours=24

	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case $1 in
		-m | --mode)
			mode="$2"
			shift 2
			;;
		-t | --title)
			title="$2"
			shift 2
			;;
		-e | --expire)
			expiration_hours="$2"
			shift 2
			;;
		-h | --help)
			usage
			exit 0
			;;
		-*)
			echo "Unknown option: $1" >&2
			usage
			exit 1
			;;
		*)
			break
			;;
		esac
	done

	if [[ $# -lt 3 ]]; then
		echo "Error: Missing required arguments" >&2
		usage
		exit 1
	fi

	local bucket="$1"
	local key="$2"
	local channel="$3"

	if ! check_dependencies; then
		exit 1
	fi

	local filename="${key##*/}"
	local display_text="${title:-$filename}"

	case "$mode" in
	upload)
		upload_s3_to_slack "$bucket" "$key" "$channel" "$title"
		;;
	link)
		local url
		if ! url=$(generate_presigned_url "$bucket" "$key" "$expiration_hours"); then
			exit 1
		fi
		create_link_block "$url" "$display_text"
		;;
	image)
		local url
		if ! url=$(generate_presigned_url "$bucket" "$key" "$expiration_hours"); then
			exit 1
		fi
		create_image_block "$url" "$display_text"
		;;
	*)
		echo "Error: Invalid mode: $mode. Must be one of: upload, link, image" >&2
		exit 1
		;;
	esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
