# AWS Integration Guide: Actions and S3 Content

This guide covers secure pathways for integrating Slack Block Kit actions with AWS infrastructure, specifically:
1. Triggering API requests to Kubernetes pods running in AWS VPC
2. Downloading and displaying S3 content in Slack messages

## Table of Contents

- [Actions → Kubernetes Pods in AWS VPC](#actions--kubernetes-pods-in-aws-vpc)
- [S3 Content in Slack Messages](#s3-content-in-slack-messages)
- [Security Best Practices](#security-best-practices)
- [Implementation Examples](#implementation-examples)

---

## Actions → Kubernetes Pods in AWS VPC

### Overview

When users click buttons in Slack, the action handler needs to securely communicate with Kubernetes pods running in a private AWS VPC. Since Slack's interactive components require a publicly accessible HTTPS endpoint, you need a secure intermediary.

### Architecture Options

#### Option 1: API Gateway + VPC Link (Recommended)

**Architecture:**
```
Slack → Python Server → AWS API Gateway → VPC Link → Private Load Balancer → K8s Service
```

**Benefits:**
- ✅ No public exposure of K8s pods
- ✅ AWS-managed authentication/authorization
- ✅ Built-in rate limiting and monitoring
- ✅ No VPN or bastion hosts needed
- ✅ Supports request signing and IAM roles

**Setup Steps:**

1. **Create VPC Link:**
   ```bash
   aws apigatewayv2 create-vpc-link \
     --name slack-k8s-vpc-link \
     --subnet-ids subnet-xxx subnet-yyy \
     --security-group-ids sg-xxx
   ```

2. **Create API Gateway HTTP API:**
   ```bash
   aws apigatewayv2 create-api \
     --name slack-k8s-api \
     --protocol-type HTTP \
     --cors-configuration AllowOrigins=*
   ```

3. **Create Integration:**
   ```bash
   aws apigatewayv2 create-integration \
     --api-id $API_ID \
     --integration-type HTTP_PROXY \
     --integration-uri http://internal-k8s-lb.elb.amazonaws.com/api \
     --integration-method ANY \
     --connection-id $VPC_LINK_ID \
     --connection-type VPC_LINK
   ```

4. **Update Python Server:**
   - Modify `python/server.py` to forward requests to API Gateway
   - Use AWS SDK or requests library with IAM signing

#### Option 2: AWS App Runner / ECS Fargate with VPC Configuration

**Architecture:**
```
Slack → App Runner/ECS (in VPC) → K8s Service (private)
```

**Benefits:**
- ✅ Serverless/managed container service
- ✅ Direct VPC access without API Gateway
- ✅ Simpler networking model
- ✅ Auto-scaling built-in

**Setup Steps:**

1. **Deploy Python Server to App Runner:**
   ```yaml
   # apprunner.yaml
   version: 1.0
   runtime: python3
   build:
     commands:
       build:
         - pip install -r requirements.txt
   run:
     runtime-version: 3.9
     command: python server.py
     network:
       port: 3000
       env: PORT
   ```

2. **Configure VPC Access:**
   - In App Runner console, configure VPC connector
   - Point to your K8s cluster's VPC
   - Set security groups to allow traffic to K8s services

#### Option 3: AWS PrivateLink (Most Secure)

**Architecture:**
```
Slack → Python Server → VPC Endpoint → PrivateLink → K8s Service
```

**Benefits:**
- ✅ Most secure option (no public internet)
- ✅ Private connectivity only
- ✅ AWS-managed encryption

**Considerations:**
- Requires VPC endpoint in same region
- More complex setup
- Higher cost

### Implementation: Enhanced Python Server

Here's how to modify the Python server to securely call K8s APIs:

```python
import boto3
import requests
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
import os

# Configuration
API_GATEWAY_URL = os.getenv('API_GATEWAY_URL', '')
K8S_API_URL = os.getenv('K8S_API_URL', '')  # Direct VPC URL if using Option 2
USE_API_GATEWAY = os.getenv('USE_API_GATEWAY', 'true').lower() == 'true'

def sign_request(url, method='GET', headers=None, data=None):
    """Sign request with AWS SigV4 for API Gateway"""
    session = boto3.Session()
    credentials = session.get_credentials()
    
    request = AWSRequest(method=method, url=url, headers=headers or {}, data=data)
    SigV4Auth(credentials, 'execute-api', session.region_name).add_auth(request)
    
    return dict(request.headers)

def call_k8s_api(action_id, payload_data):
    """Call Kubernetes API securely"""
    endpoint_map = {
        'deploy_service': '/api/v1/deploy',
        'scale_pods': '/api/v1/scale',
        'get_status': '/api/v1/status',
    }
    
    endpoint = endpoint_map.get(action_id, '/api/v1/default')
    url = f"{API_GATEWAY_URL}{endpoint}" if USE_API_GATEWAY else f"{K8S_API_URL}{endpoint}"
    
    headers = {'Content-Type': 'application/json'}
    
    if USE_API_GATEWAY:
        # Sign request for API Gateway
        headers = sign_request(url, method='POST', headers=headers, data=json.dumps(payload_data))
    
    response = requests.post(
        url,
        headers=headers,
        json=payload_data,
        timeout=30,
    )
    response.raise_for_status()
    return response.json()

@app.route('/slack/actions', methods=['POST'])
def handle_actions():
    try:
        payload = parse_payload()
        actions = payload.get('actions', [])
        action_id = actions[0].get('action_id') if actions else None
        
        if not action_id:
            return Response('Missing action_id', status=400)
        
        user_id = payload.get('user', {}).get('id')
        channel_id = payload.get('channel', {}).get('id')
        
        # Handle K8s-related actions
        if action_id.startswith('k8s_'):
            try:
                k8s_response = call_k8s_api(action_id, {
                    'user_id': user_id,
                    'channel_id': channel_id,
                    'action_data': actions[0].get('value', '{}'),
                })
                
                # Send result back to Slack
                send_slack_message(
                    channel_id,
                    f"✅ Action completed: {k8s_response.get('message', 'Success')}"
                )
            except Exception as e:
                logger.error(f"K8s API error: {e}", exc_info=True)
                send_slack_message(
                    channel_id,
                    f"❌ Error: {str(e)}"
                )
                return Response('K8s API error', status=500)
        
        # ... existing action handlers ...
        
        return Response('', status=200)
    except Exception as e:
        logger.error(f'Error: {e}', exc_info=True)
        return Response('Internal server error', status=500)
```

### Security Considerations

1. **Authentication:**
   - Use AWS IAM roles for API Gateway authentication
   - Implement request signing (SigV4) for API Gateway calls
   - Use service account tokens for direct K8s access (if Option 2)

2. **Authorization:**
   - Validate Slack request signatures (see Slack docs)
   - Implement user-based authorization (check if user has permission)
   - Use K8s RBAC for pod access control

3. **Network Security:**
   - Keep K8s services private (no public IPs)
   - Use security groups to restrict access
   - Enable VPC Flow Logs for monitoring

4. **Secrets Management:**
   - Store K8s credentials in AWS Secrets Manager
   - Use IAM roles instead of access keys
   - Rotate credentials regularly

---

## S3 Content in Slack Messages

### Overview

You can display S3 content in Slack messages through several methods:
1. **Pre-signed URLs** - Generate temporary URLs for S3 objects
2. **Slack File Upload** - Download from S3 and upload to Slack
3. **Image Blocks** - Direct display of images from S3 (via pre-signed URLs)
4. **File Blocks** - Links to downloadable S3 content

### Option 1: Pre-signed URLs (Recommended for Public/Shared Content)

**Use Case:** When you want to share S3 content that users can access directly.

**Implementation:**

```python
import boto3
from datetime import timedelta

def generate_s3_presigned_url(bucket, key, expiration_hours=24):
    """Generate pre-signed URL for S3 object"""
    s3_client = boto3.client('s3')
    
    url = s3_client.generate_presigned_url(
        'get_object',
        Params={'Bucket': bucket, 'Key': key},
        ExpiresIn=int(timedelta(hours=expiration_hours).total_seconds())
    )
    return url

def create_s3_link_block(bucket, key, display_text=None):
    """Create Slack block with S3 link"""
    url = generate_s3_presigned_url(bucket, key)
    filename = key.split('/')[-1] if '/' in key else key
    
    return {
        "type": "section",
        "text": {
            "type": "mrkdwn",
            "text": f"📎 <{url}|{display_text or filename}>"
        }
    }
```

**Slack Message Example:**
```json
{
  "blocks": [
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "Report available: <https://s3-presigned-url...|download-report.pdf>"
      }
    }
  ]
}
```

### Option 2: Download and Upload to Slack (Recommended for Private Content)

**Use Case:** When S3 content is private and you want it accessible through Slack's file system.

**Implementation:**

```python
import boto3
import tempfile
import os

def download_and_upload_to_slack(bucket, key, channel_id, title=None):
    """Download from S3 and upload to Slack"""
    s3_client = boto3.client('s3')
    
    # Download to temporary file
    with tempfile.NamedTemporaryFile(delete=False, suffix=os.path.splitext(key)[1]) as tmp_file:
        s3_client.download_fileobj(bucket, key, tmp_file)
        tmp_path = tmp_file.name
    
    try:
        # Use existing file upload functionality
        # This would integrate with your file-upload.sh script
        filename = key.split('/')[-1] if '/' in key else key
        title = title or filename
        
        # Call Slack files.upload API
        with open(tmp_path, 'rb') as f:
            response = requests.post(
                'https://slack.com/api/files.upload',
                headers={
                    'Authorization': f'Bearer {SLACK_BOT_USER_OAUTH_TOKEN}',
                },
                data={
                    'channels': channel_id,
                    'title': title,
                },
                files={'file': (filename, f, 'application/octet-stream')},
                timeout=60,
            )
        
        response.raise_for_status()
        return response.json()
    finally:
        os.unlink(tmp_path)  # Clean up temp file
```

### Option 3: Image Blocks with S3 Pre-signed URLs

**Use Case:** Display images directly in Slack messages.

**Implementation:**

```python
def create_s3_image_block(bucket, key, alt_text="Image"):
    """Create image block with S3 pre-signed URL"""
    url = generate_s3_presigned_url(bucket, key, expiration_hours=168)  # 7 days
    
    return {
        "type": "image",
        "image_url": url,
        "alt_text": alt_text
    }
```

**Note:** Slack requires image URLs to be publicly accessible or use HTTPS. Pre-signed URLs work perfectly for this.

### Option 4: Enhanced File Upload Script for S3

Create a new script that integrates S3 download with existing file upload:

```bash
#!/usr/bin/env bash
# bin/s3-to-slack.sh
# Downloads from S3 and uploads to Slack

set -eo pipefail

# Usage: s3-to-slack.sh <bucket> <key> <channel> [title]

BUCKET="$1"
KEY="$2"
CHANNEL="$3"
TITLE="${4:-${KEY##*/}}"

if [[ -z "$BUCKET" ]] || [[ -z "$KEY" ]] || [[ -z "$CHANNEL" ]]; then
    echo "Usage: s3-to-slack.sh <bucket> <key> <channel> [title]" >&2
    exit 1
fi

# Download from S3 to temp file
TMP_FILE=$(mktemp /tmp/s3-slack-XXXXXX)
trap 'rm -f "$TMP_FILE"' EXIT

echo "Downloading s3://${BUCKET}/${KEY}..." >&2
aws s3 cp "s3://${BUCKET}/${KEY}" "$TMP_FILE" || {
    echo "Failed to download from S3" >&2
    exit 1
}

# Use existing file upload functionality
export CHANNEL="$CHANNEL"
export SLACK_BOT_USER_OAUTH_TOKEN="${SLACK_BOT_USER_OAUTH_TOKEN}"

jq -n \
    --arg path "$TMP_FILE" \
    --arg title "$TITLE" \
    '{
        file: {
            path: $path,
            title: $title
        }
    }' | file-upload.sh
```

### Security Considerations for S3

1. **Pre-signed URLs:**
   - Set appropriate expiration times (24-168 hours typical)
   - Use IAM policies to restrict which objects can be accessed
   - Monitor CloudTrail for S3 access patterns

2. **IAM Permissions:**
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Action": [
           "s3:GetObject",
           "s3:GeneratePresignedUrl"
         ],
         "Resource": "arn:aws:s3:::your-bucket/slack-content/*"
       }
     ]
   }
   ```

3. **Bucket Policies:**
   - Use bucket policies to restrict public access
   - Enable S3 bucket versioning for important content
   - Enable S3 access logging

4. **Content Security:**
   - Scan uploaded files for malware (if downloading)
   - Validate file types and sizes
   - Use S3 lifecycle policies to manage storage costs

---

## Implementation Examples

### Example 1: Action Button to Trigger K8s Deployment

**Slack Message:**
```json
{
  "blocks": [
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "Deploy new version to production?"
      }
    },
    {
      "type": "actions",
      "elements": [
        {
          "type": "button",
          "text": {
            "type": "plain_text",
            "text": "Deploy"
          },
          "action_id": "k8s_deploy",
          "value": "{\"namespace\":\"production\",\"deployment\":\"app-v2\"}",
          "style": "primary"
        }
      ]
    }
  ]
}
```

**Python Handler:**
```python
if action_id == 'k8s_deploy':
    import json
    deploy_config = json.loads(actions[0].get('value', '{}'))
    
    k8s_response = call_k8s_api('deploy_service', {
        'namespace': deploy_config.get('namespace'),
        'deployment': deploy_config.get('deployment'),
        'user': user_id,
    })
    
    send_slack_message(channel_id, f"🚀 Deployment initiated: {k8s_response['status']}")
```

### Example 2: Display S3 Report in Slack

**Python Function:**
```python
def send_s3_report_to_slack(channel_id, bucket, report_key):
    """Send S3 report as Slack file"""
    file_metadata = download_and_upload_to_slack(
        bucket, 
        report_key, 
        channel_id,
        title=f"Report: {report_key.split('/')[-1]}"
    )
    
    send_slack_message(
        channel_id,
        f"📊 Report uploaded: {file_metadata['file']['permalink']}"
    )
```

### Example 3: Image Gallery from S3

**Python Function:**
```python
def send_s3_images_to_slack(channel_id, bucket, image_keys):
    """Send multiple S3 images as image blocks"""
    blocks = []
    
    for key in image_keys:
        blocks.append(create_s3_image_block(bucket, key, alt_text=key.split('/')[-1]))
    
    send_slack_message(channel_id, blocks=blocks)
```

---

## Security Best Practices Summary

### For K8s Integration:
- ✅ Use API Gateway with VPC Link (no public K8s exposure)
- ✅ Implement request signing (AWS SigV4)
- ✅ Validate Slack request signatures
- ✅ Use IAM roles, not access keys
- ✅ Enable VPC Flow Logs
- ✅ Implement rate limiting

### For S3 Integration:
- ✅ Use pre-signed URLs with short expiration
- ✅ Restrict IAM permissions to specific buckets/prefixes
- ✅ Enable S3 access logging
- ✅ Validate file types and sizes
- ✅ Use bucket policies to prevent public access
- ✅ Consider CloudFront for public content (better performance)

---

## Next Steps

1. **Choose your architecture** based on security requirements and complexity tolerance
2. **Set up AWS resources** (API Gateway, VPC Link, IAM roles)
3. **Update Python server** with K8s/S3 integration code
4. **Test with dry-run** before production deployment
5. **Monitor** CloudWatch logs and Slack API usage

## Additional Resources

- [AWS API Gateway VPC Link](https://docs.aws.amazon.com/apigateway/latest/developerguide/set-up-private-integration.html)
- [AWS PrivateLink](https://docs.aws.amazon.com/vpc/latest/privatelink/)
- [S3 Pre-signed URLs](https://docs.aws.amazon.com/AmazonS3/latest/userguide/ShareObjectPreSignedURL.html)
- [Slack File Uploads](https://api.slack.com/methods/files.upload)
- [Slack Interactive Components](https://api.slack.com/interactivity)
