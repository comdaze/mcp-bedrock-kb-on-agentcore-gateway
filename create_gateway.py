#!/usr/bin/env python3
"""
Create AgentCore Gateway for Bedrock KB MCP Server
"""
import boto3
import json
import sys
import os
import time

def create_gateway_role(iam_client, role_name, account_id, region):
    """Create IAM role for Gateway"""
    trust_policy = {
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {
                "Service": "bedrock-agentcore.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }]
    }
    
    try:
        response = iam_client.create_role(
            RoleName=role_name,
            AssumeRolePolicyDocument=json.dumps(trust_policy),
            Description="Role for Bedrock KB MCP Gateway"
        )
        print(f"✓ IAM Role created: {role_name}")
        
        # Attach Lambda invoke policy
        policy_document = {
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Action": "lambda:InvokeFunction",
                "Resource": f"arn:aws:lambda:{region}:{account_id}:function:*"
            }]
        }
        
        iam_client.put_role_policy(
            RoleName=role_name,
            PolicyName="LambdaInvokePolicy",
            PolicyDocument=json.dumps(policy_document)
        )
        print(f"✓ Lambda invoke policy attached")
        
        # Wait for role to be available
        time.sleep(10)
        
        return response['Role']['Arn']
    except iam_client.exceptions.EntityAlreadyExistsException:
        print(f"⚠ IAM Role already exists: {role_name}")
        return f"arn:aws:iam::{account_id}:role/{role_name}"

def create_gateway(region, gateway_name, role_arn, user_pool_id, client_id):
    """Create AgentCore Gateway"""
    client = boto3.client('bedrock-agentcore-control', region_name=region)
    
    # Cognito discovery URL
    discovery_url = f"https://cognito-idp.{region}.amazonaws.com/{user_pool_id}/.well-known/openid-configuration"
    
    try:
        response = client.create_gateway(
            name=gateway_name,
            description="Bedrock Knowledge Base MCP Server Gateway",
            roleArn=role_arn,
            protocolType="MCP",
            authorizerType="CUSTOM_JWT",
            authorizerConfiguration={
                "customJWTAuthorizer": {
                    "discoveryUrl": discovery_url,
                    "allowedClients": [client_id]
                }
            }
        )
        
        gateway_id = response['gatewayId']
        gateway_url = response['gatewayUrl']
        
        print(f"✓ Gateway created successfully")
        print(f"  Gateway ID: {gateway_id}")
        print(f"  Gateway URL: {gateway_url}")
        
        return gateway_id, gateway_url
        
    except Exception as e:
        print(f"✗ Error creating gateway: {str(e)}")
        sys.exit(1)

def main():
    # Load from environment
    region = os.environ.get('AWS_REGION', 'us-east-1')
    gateway_name = os.environ.get('GATEWAY_NAME', 'bedrock-kb-mcp-gateway')
    user_pool_id = os.environ.get('USER_POOL_ID')
    client_id = os.environ.get('CLIENT_ID')
    
    if not user_pool_id:
        print("✗ Error: USER_POOL_ID environment variable is required")
        sys.exit(1)
    
    if not client_id:
        print("✗ Error: CLIENT_ID environment variable is required")
        sys.exit(1)
    
    # Get account ID
    sts_client = boto3.client('sts')
    account_id = sts_client.get_caller_identity()['Account']
    
    # Create IAM role
    iam_client = boto3.client('iam')
    role_name = f"{gateway_name}-role"
    role_arn = create_gateway_role(iam_client, role_name, account_id, region)
    
    # Create Gateway
    gateway_id, gateway_url = create_gateway(
        region, gateway_name, role_arn, user_pool_id, client_id
    )
    
    # Output for shell script
    print(f"\nGATEWAY_ID={gateway_id}")
    print(f"GATEWAY_URL={gateway_url}")

if __name__ == "__main__":
    main()
