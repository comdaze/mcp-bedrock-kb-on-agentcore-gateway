#!/usr/bin/env python3
"""
Add Gateway Target to AgentCore Gateway
Reads configuration from environment variables
"""
import boto3
import json
import sys
import os

def load_config():
    """Load configuration from environment variables"""
    gateway_id = os.environ.get('GATEWAY_ID')
    lambda_arn = os.environ.get('LAMBDA_ARN')
    region = os.environ.get('AWS_REGION', 'us-east-1')
    
    if not gateway_id:
        print("Error: GATEWAY_ID environment variable is required")
        sys.exit(1)
    
    if not lambda_arn:
        print("Error: LAMBDA_ARN environment variable is required")
        sys.exit(1)
    
    return gateway_id, lambda_arn, region

def create_gateway_target(gateway_id: str, lambda_arn: str, region: str):
    """Create Gateway Target with tool specifications"""
    client = boto3.client('bedrock-agentcore-control', region_name=region)
    
    # Tool specifications
    tool_schema = [
        {
            "name": "ListKnowledgeBases",
            "description": "List all available Amazon Bedrock Knowledge Bases and their data sources",
            "inputSchema": {
                "type": "object",
                "properties": {},
                "required": []
            }
        },
        {
            "name": "QueryKnowledgeBases",
            "description": "Query Amazon Bedrock Knowledge Base using natural language. Returns relevant information from the knowledge base.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Natural language query to search"
                    },
                    "knowledge_base_id": {
                        "type": "string",
                        "description": "Knowledge Base ID (optional, uses default if not provided)"
                    },
                    "number_of_results": {
                        "type": "integer",
                        "description": "Number of results to return (default: 10, max: 100)"
                    }
                },
                "required": ["query"]
            }
        }
    ]
    
    try:
        print(f"\nCreating Gateway Target...")
        response = client.create_gateway_target(
            gatewayIdentifier=gateway_id,
            name="BedrockKBMCPTarget",
            description="Bedrock Knowledge Base MCP Target",
            targetConfiguration={
                "mcp": {
                    "lambda": {
                        "lambdaArn": lambda_arn,
                        "toolSchema": {
                            "inlinePayload": tool_schema
                        }
                    }
                }
            },
            credentialProviderConfigurations=[
                {
                    "credentialProviderType": "GATEWAY_IAM_ROLE"
                }
            ]
        )
        
        target_id = response.get('targetId')
        print(f"✓ Gateway Target created successfully")
        print(f"  Target ID: {target_id}")
        print(f"  Tools: ListKnowledgeBases, QueryKnowledgeBases")
        
        return target_id
        
    except Exception as e:
        print(f"✗ Failed to create Gateway Target: {e}")
        if "already exists" in str(e).lower() or "AlreadyExistsException" in str(e):
            print(f"  Target may already exist. Use update_gateway_target.py to update.")
        sys.exit(1)

def main():
    print("=== Add Gateway Target ===\n")
    
    gateway_id, lambda_arn, region = load_config()
    
    print(f"Gateway ID: {gateway_id}")
    print(f"Lambda ARN: {lambda_arn}")
    print(f"Region: {region}")
    
    create_gateway_target(gateway_id, lambda_arn, region)
    
    print("\n✓ Gateway Target configuration complete!")

if __name__ == "__main__":
    main()
