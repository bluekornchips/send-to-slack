#!/usr/bin/env python3
"""
AWS Integration module for Slack Block Kit actions
Provides secure pathways to:
- Call Kubernetes APIs via AWS API Gateway + VPC Link
- Download and display S3 content in Slack messages
"""

import json
import logging
import os
import tempfile
from datetime import timedelta
from typing import Dict, Optional, Any

import boto3
import requests
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest

logger = logging.getLogger(__name__)

# AWS Configuration
API_GATEWAY_URL = os.getenv('API_GATEWAY_URL', '')
K8S_API_URL = os.getenv('K8S_API_URL', '')  # Direct VPC URL if not using API Gateway
USE_API_GATEWAY = os.getenv('USE_API_GATEWAY', 'true').lower() == 'true'
AWS_REGION = os.getenv('AWS_REGION', 'us-east-1')

# S3 Configuration
S3_BUCKET = os.getenv('S3_BUCKET', '')
S3_PREFIX = os.getenv('S3_PREFIX', 'slack-content/')
PRESIGNED_URL_EXPIRATION_HOURS = int(os.getenv('PRESIGNED_URL_EXPIRATION_HOURS', '24'))


class K8sAPIClient:
    """Client for securely calling Kubernetes APIs via AWS"""
    
    def __init__(self):
        self.api_gateway_url = API_GATEWAY_URL
        self.k8s_api_url = K8S_API_URL
        self.use_api_gateway = USE_API_GATEWAY
        self.session = boto3.Session(region_name=AWS_REGION)
    
    def _sign_request(self, url: str, method: str = 'GET', headers: Optional[Dict] = None, data: Optional[str] = None) -> Dict[str, str]:
        """Sign request with AWS SigV4 for API Gateway authentication"""
        credentials = self.session.get_credentials()
        if not credentials:
            raise ValueError('AWS credentials not found. Ensure IAM role or credentials are configured.')
        
        request = AWSRequest(method=method, url=url, headers=headers or {}, data=data)
        SigV4Auth(credentials, 'execute-api', AWS_REGION).add_auth(request)
        
        return dict(request.headers)
    
    def call_api(self, action_id: str, payload_data: Dict[str, Any]) -> Dict[str, Any]:
        """
        Call Kubernetes API securely
        
        Args:
            action_id: Action identifier (maps to endpoint)
            payload_data: Data to send to K8s API
            
        Returns:
            Response JSON from K8s API
        """
        # Map action IDs to endpoints
        endpoint_map = {
            'k8s_deploy': '/api/v1/deploy',
            'k8s_scale': '/api/v1/scale',
            'k8s_status': '/api/v1/status',
            'k8s_logs': '/api/v1/logs',
            'k8s_restart': '/api/v1/restart',
        }
        
        endpoint = endpoint_map.get(action_id, '/api/v1/default')
        
        if self.use_api_gateway:
            if not self.api_gateway_url:
                raise ValueError('API_GATEWAY_URL must be set when using API Gateway')
            url = f"{self.api_gateway_url}{endpoint}"
        else:
            if not self.k8s_api_url:
                raise ValueError('K8S_API_URL must be set when not using API Gateway')
            url = f"{self.k8s_api_url}{endpoint}"
        
        headers = {'Content-Type': 'application/json'}
        
        # Sign request if using API Gateway
        if self.use_api_gateway:
            headers = self._sign_request(url, method='POST', headers=headers, data=json.dumps(payload_data))
        
        logger.info(f'Calling K8s API: {url} with action_id: {action_id}')
        
        response = requests.post(
            url,
            headers=headers,
            json=payload_data,
            timeout=30,
        )
        
        response.raise_for_status()
        return response.json()


class S3ContentManager:
    """Manager for downloading and sharing S3 content in Slack"""
    
    def __init__(self):
        self.bucket = S3_BUCKET
        self.prefix = S3_PREFIX
        self.s3_client = boto3.client('s3', region_name=AWS_REGION)
        self.expiration_hours = PRESIGNED_URL_EXPIRATION_HOURS
    
    def generate_presigned_url(self, key: str, expiration_hours: Optional[int] = None) -> str:
        """
        Generate pre-signed URL for S3 object
        
        Args:
            key: S3 object key
            expiration_hours: URL expiration time in hours (defaults to configured value)
            
        Returns:
            Pre-signed URL string
        """
        expiration = expiration_hours or self.expiration_hours
        expiration_seconds = int(timedelta(hours=expiration).total_seconds())
        
        url = self.s3_client.generate_presigned_url(
            'get_object',
            Params={'Bucket': self.bucket, 'Key': key},
            ExpiresIn=expiration_seconds
        )
        
        logger.info(f'Generated pre-signed URL for s3://{self.bucket}/{key} (expires in {expiration} hours)')
        return url
    
    def create_link_block(self, key: str, display_text: Optional[str] = None) -> Dict[str, Any]:
        """
        Create Slack section block with S3 file link
        
        Args:
            key: S3 object key
            display_text: Text to display in Slack (defaults to filename)
            
        Returns:
            Slack block JSON
        """
        url = self.generate_presigned_url(key)
        filename = key.split('/')[-1] if '/' in key else key
        text = display_text or filename
        
        return {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"📎 <{url}|{text}>"
            }
        }
    
    def create_image_block(self, key: str, alt_text: Optional[str] = None) -> Dict[str, Any]:
        """
        Create Slack image block with S3 image URL
        
        Args:
            key: S3 object key (should be an image)
            alt_text: Alt text for image (defaults to filename)
            
        Returns:
            Slack image block JSON
        """
        url = self.generate_presigned_url(key, expiration_hours=168)  # 7 days for images
        filename = key.split('/')[-1] if '/' in key else key
        alt = alt_text or filename
        
        return {
            "type": "image",
            "image_url": url,
            "alt_text": alt
        }
    
    def download_and_upload_to_slack(
        self, 
        key: str, 
        slack_bot_token: str, 
        channel_id: str, 
        title: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Download file from S3 and upload to Slack
        
        Args:
            key: S3 object key
            slack_bot_token: Slack bot OAuth token
            channel_id: Slack channel ID
            title: Title for Slack file (defaults to filename)
            
        Returns:
            Slack API response with file metadata
        """
        filename = key.split('/')[-1] if '/' in key else key
        title = title or filename
        
        # Download to temporary file
        with tempfile.NamedTemporaryFile(delete=False, suffix=os.path.splitext(key)[1]) as tmp_file:
            try:
                logger.info(f'Downloading s3://{self.bucket}/{key} to temporary file')
                self.s3_client.download_fileobj(self.bucket, key, tmp_file)
                tmp_path = tmp_file.name
                
                # Determine content type
                content_type = 'application/octet-stream'
                if key.endswith('.pdf'):
                    content_type = 'application/pdf'
                elif key.endswith(('.png', '.jpg', '.jpeg', '.gif')):
                    content_type = f'image/{key.split(".")[-1]}'
                elif key.endswith('.json'):
                    content_type = 'application/json'
                elif key.endswith('.txt'):
                    content_type = 'text/plain'
                
                # Upload to Slack
                logger.info(f'Uploading {filename} to Slack channel {channel_id}')
                with open(tmp_path, 'rb') as f:
                    response = requests.post(
                        'https://slack.com/api/files.upload',
                        headers={
                            'Authorization': f'Bearer {slack_bot_token}',
                        },
                        data={
                            'channels': channel_id,
                            'title': title,
                            'initial_comment': f'File from S3: {key}',
                        },
                        files={'file': (filename, f, content_type)},
                        timeout=60,
                    )
                
                response.raise_for_status()
                result = response.json()
                
                if not result.get('ok'):
                    raise RuntimeError(f'Slack API error: {result.get("error")}')
                
                logger.info(f'Successfully uploaded {filename} to Slack')
                return result
                
            finally:
                # Clean up temporary file
                if os.path.exists(tmp_path):
                    os.unlink(tmp_path)
                    logger.debug(f'Cleaned up temporary file: {tmp_path}')
    
    def list_objects(self, prefix: Optional[str] = None, max_keys: int = 100) -> list:
        """
        List objects in S3 bucket
        
        Args:
            prefix: S3 prefix to filter (defaults to configured prefix)
            max_keys: Maximum number of keys to return
            
        Returns:
            List of object keys
        """
        prefix = prefix or self.prefix
        
        response = self.s3_client.list_objects_v2(
            Bucket=self.bucket,
            Prefix=prefix,
            MaxKeys=max_keys
        )
        
        keys = [obj['Key'] for obj in response.get('Contents', [])]
        logger.info(f'Found {len(keys)} objects with prefix {prefix}')
        return keys


# Convenience functions for easy import
def get_k8s_client() -> K8sAPIClient:
    """Get configured K8s API client"""
    return K8sAPIClient()


def get_s3_manager() -> S3ContentManager:
    """Get configured S3 content manager"""
    if not S3_BUCKET:
        raise ValueError('S3_BUCKET environment variable must be set')
    return S3ContentManager()
