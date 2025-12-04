#!/usr/bin/env python3
"""
Update Gateway Target in AgentCore Gateway
Reads configuration from environment variables
"""
import boto3
import json
import sys
import os

def load_config():
    """Load configuration from environment variables"""
    gateway_id = os.environ.get('GATEWAY_ID')
    target_id = os.environ.get('TARGET_ID')
    lambda_arn = os.environ.get('LAMBDA_ARN')
    region = os.environ.get('AWS_REGION', 'us-east-1')
    tool_name = os.environ.get('TOOL_NAME', 'QueryKnowledgeBases')
    
    if not gateway_id:
        print("Error: GATEWAY_ID environment variable is required")
        sys.exit(1)
    
    if not target_id:
        print("Error: TARGET_ID environment variable is required")
        sys.exit(1)
    
    if not lambda_arn:
        print("Error: LAMBDA_ARN environment variable is required")
        sys.exit(1)
    
    return gateway_id, target_id, lambda_arn, region, tool_name

def get_tool_spec(tool_name: str):
    """Get tool specification by name"""
    if tool_name == "ListKnowledgeBases":
        return {
            "name": "ListKnowledgeBases",
            "description": "List all available Amazon Bedrock Knowledge Bases and their data sources",
            "inputSchema": {
                "json": {
                    "type": "object",
                    "properties": {},
                    "required": []
                }
            }
        }
    elif tool_name == "QueryKnowledgeBases":
        return {
            "name": "QueryKnowledgeBases",
            "description": "Query Amazon Bedrock Knowledge Base using natural language. Returns relevant information from the knowledge base.",
            "inputSchema": {
                "json": {
                    "type": "object",
                    "properties": {
                        "query": {
                            "type": "string",
                            "description": "Natural language query to search in the knowledge base"
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
        }
    else:
        raise ValueError(f"Unknown tool name: {tool_name}")

def update_gateway_target(gateway_id: str, target_id: str, lambda_arn: str, 
                         region: str, tool_name: str):
    """Update Gateway Target"""
    client = boto3.client('bedrock-agent-runtime', region_name=region)
    
    tool_spec = get_tool_spec(tool_name)
    
    try:
        print(f"\nUpdating Gateway Target for {tool_name}...")
        response = client.update_gateway_target(
            gatewayId=gateway_id,
            targetId=target_id,
            targetArn=lambda_arn,
            toolSpec=tool_spec
        )
        print(f"✓ {tool_name} Target updated successfully")
        print(json.dumps(response, indent=2, ensure_ascii=False, default=str))
        return True
    except Exception as e:
        print(f"✗ Failed to update target: {e}")
        return False

def main():
    """Main function"""
    print("=== Update Gateway Target ===\n")
    
    gateway_id, target_id, lambda_arn, region, tool_name = load_config()
    
    print(f"Gateway ID: {gateway_id}")
    print(f"Target ID: {target_id}")
    print(f"Lambda ARN: {lambda_arn}")
    print(f"Region: {region}")
    print(f"Tool Name: {tool_name}")
    
    success = update_gateway_target(gateway_id, target_id, lambda_arn, region, tool_name)
    
    if not success:
        sys.exit(1)

if __name__ == "__main__":
    main()
