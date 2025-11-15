# Quick Start: AWS Integration

This guide provides step-by-step instructions for setting up AWS integration with Slack Block Kit actions.

## Prerequisites

- AWS account with appropriate permissions
- Slack app with interactive components configured
- Python 3.9+ with pip
- AWS CLI configured (`aws configure`)

## Part 1: K8s Integration Setup

### Step 1: Create API Gateway with VPC Link

```bash
# Set variables
VPC_ID="vpc-xxxxx"
SUBNET_IDS="subnet-xxx,subnet-yyy"
SECURITY_GROUP_ID="sg-xxx"
K8S_LB_DNS="internal-k8s-lb-123456789.us-east-1.elb.amazonaws.com"

# Create VPC Link
VPC_LINK_ID=$(aws apigatewayv2 create-vpc-link \
  --name slack-k8s-vpc-link \
  --subnet-ids $SUBNET_IDS \
  --security-group-ids $SECURITY_GROUP_ID \
  --query 'VpcLinkId' --output text)

echo "VPC Link ID: $VPC_LINK_ID"

# Create HTTP API
API_ID=$(aws apigatewayv2 create-api \
  --name slack-k8s-api \
  --protocol-type HTTP \
  --query 'ApiId' --output text)

echo "API ID: $API_ID"

# Create integration
INTEGRATION_ID=$(aws apigatewayv2 create-integration \
  --api-id $API_ID \
  --integration-type HTTP_PROXY \
  --integration-uri "http://${K8S_LB_DNS}/api" \
  --integration-method ANY \
  --connection-id $VPC_LINK_ID \
  --connection-type VPC_LINK \
  --query 'IntegrationId' --output text)

# Create route
ROUTE_ID=$(aws apigatewayv2 create-route \
  --api-id $API_ID \
  --route-key "ANY /{proxy+}" \
  --target "integrations/${INTEGRATION_ID}" \
  --query 'RouteId' --output text)

# Deploy API
STAGE=$(aws apigatewayv2 create-stage \
  --api-id $API_ID \
  --stage-name prod \
  --auto-deploy \
  --query 'StageName' --output text)

# Get API Gateway URL
API_GATEWAY_URL=$(aws apigatewayv2 get-api \
  --api-id $API_ID \
  --query 'ApiEndpoint' --output text)

echo "API Gateway URL: ${API_GATEWAY_URL}"
```

### Step 2: Configure IAM Role

Create an IAM role for your Python server with permissions to invoke API Gateway:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "execute-api:Invoke"
      ],
      "Resource": "arn:aws:execute-api:*:*:${API_ID}/*"
    }
  ]
}
```

### Step 3: Update Python Server

```bash
cd python
export API_GATEWAY_URL="https://${API_ID}.execute-api.us-east-1.amazonaws.com/prod"
export AWS_REGION="us-east-1"
export SLACK_BOT_USER_OAUTH_TOKEN="xoxb-your-token"
export USE_API_GATEWAY="true"

# Install dependencies
pip install -r pyproject.toml

# Run enhanced server
python server_aws_example.py
```

## Part 2: S3 Integration Setup

### Step 1: Create S3 Bucket

```bash
BUCKET_NAME="slack-content-$(date +%s)"
AWS_REGION="us-east-1"

aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION}

# Upload a test file
echo "Test content" > test.txt
aws s3 cp test.txt s3://${BUCKET_NAME}/test/test.txt
```

### Step 2: Configure IAM Permissions

Create IAM policy for S3 access:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${BUCKET_NAME}",
        "arn:aws:s3:::${BUCKET_NAME}/*"
      ]
    }
  ]
}
```

### Step 3: Configure Python Server

```bash
export S3_BUCKET="${BUCKET_NAME}"
export S3_PREFIX="slack-content/"
export PRESIGNED_URL_EXPIRATION_HOURS="24"
```

### Step 4: Test S3 Integration

```bash
# Using the bash script
export SLACK_BOT_USER_OAUTH_TOKEN="xoxb-your-token"
export AWS_REGION="us-east-1"

# Create link block
./bin/s3-to-slack.sh -m link ${BUCKET_NAME} test/test.txt notifications

# Upload file to Slack
./bin/s3-to-slack.sh -m upload ${BUCKET_NAME} test/test.txt notifications
```

## Part 3: Slack App Configuration

### Step 1: Configure Interactive Components

1. Go to [api.slack.com/apps](https://api.slack.com/apps)
2. Select your app
3. Navigate to **Interactivity & Shortcuts**
4. Enable **Interactivity**
5. Set **Request URL** to your Python server endpoint:
   - Local dev: `https://your-ngrok-url.ngrok.io/slack/actions`
   - Production: `https://your-domain.com/slack/actions`

### Step 2: Verify Request Signing

The Python server should validate Slack request signatures. Add this to your server:

```python
import hmac
import hashlib
import time

def verify_slack_signature(request_body, signature, timestamp):
    """Verify Slack request signature"""
    if abs(time.time() - int(timestamp)) > 60 * 5:
        return False  # Request too old
    
    sig_basestring = f'v0:{timestamp}:{request_body}'
    my_signature = 'v0=' + hmac.new(
        SLACK_SIGNING_SECRET.encode(),
        sig_basestring.encode(),
        hashlib.sha256
    ).hexdigest()
    
    return hmac.compare_digest(my_signature, signature)
```

## Part 4: Testing

### Test K8s Action

Send a message with K8s action button:

```bash
echo '{
  "source": {
    "slack_bot_user_oauth_token": "xoxb-your-token"
  },
  "params": {
    "channel": "notifications",
    "blocks": [
      {
        "section": {
          "type": "text",
          "text": {
            "type": "mrkdwn",
            "text": "Deploy to production?"
          }
        }
      },
      {
        "actions": {
          "elements": [
            {
              "type": "button",
              "text": {
                "type": "plain_text",
                "text": "Deploy"
              },
              "action_id": "k8s_deploy",
              "value": "{\"namespace\":\"production\",\"deployment\":\"app\"}",
              "style": "primary"
            }
          ]
        }
      }
    ]
  }
}' | send-to-slack
```

### Test S3 Link

```bash
echo '{
  "source": {
    "slack_bot_user_oauth_token": "xoxb-your-token"
  },
  "params": {
    "channel": "notifications",
    "blocks": [
      {
        "section": {
          "type": "text",
          "text": {
            "type": "mrkdwn",
            "text": "Report available"
          }
        }
      },
      {
        "actions": {
          "elements": [
            {
              "type": "button",
              "text": {
                "type": "plain_text",
                "text": "View Report"
              },
              "action_id": "s3_share_link",
              "value": "{\"key\":\"reports/report.pdf\",\"title\":\"Daily Report\"}",
              "style": "primary"
            }
          ]
        }
      }
    ]
  }
}' | send-to-slack
```

## Troubleshooting

### K8s API Not Responding

1. Check VPC Link status: `aws apigatewayv2 get-vpc-link --vpc-link-id $VPC_LINK_ID`
2. Verify security groups allow traffic
3. Check K8s service is accessible from VPC
4. Review CloudWatch logs for API Gateway

### S3 Access Denied

1. Verify IAM permissions
2. Check bucket policy
3. Ensure bucket region matches AWS_REGION
4. Verify object key exists: `aws s3 ls s3://${BUCKET_NAME}/${KEY}`

### Slack Actions Not Working

1. Verify Request URL is accessible (use ngrok for local dev)
2. Check Slack app has `chat:write` scope
3. Review Python server logs
4. Validate request signature (if implemented)

## Next Steps

- Review [AWS_INTEGRATION_GUIDE.md](AWS_INTEGRATION_GUIDE.md) for detailed architecture
- Set up monitoring with CloudWatch
- Implement request rate limiting
- Add user authorization checks
- Set up CI/CD for deployments
