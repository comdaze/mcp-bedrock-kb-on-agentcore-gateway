"""
Configuration management for Bedrock KB MCP Server
"""
import os
from typing import Optional

class Config:
    """Configuration class that loads from environment variables"""
    
    def __init__(self):
        # AWS Configuration
        self.aws_region = os.environ.get('AWS_REGION', 'us-east-1')
        self.aws_account_id: Optional[str] = None  # Will be fetched dynamically
        
        # Knowledge Base Configuration
        self.default_kb_id = os.environ.get('KNOWLEDGE_BASE_ID', 'PTTWEFYB6R')
        self.kb_tag_key = os.environ.get('KB_INCLUSION_TAG_KEY', 'mcp-multirag-kb')
        self.kb_tag_value = os.environ.get('KB_TAG_VALUE', 'true')
        
        # Lambda Configuration
        self.lambda_function_name = os.environ.get('LAMBDA_FUNCTION_NAME', 'BedrockKBMCPProxy')
        self.lambda_role_name = os.environ.get('LAMBDA_ROLE_NAME', 'BedrockKBMCPLambdaRole')
        
        # Gateway Configuration (optional, loaded from environment if exists)
        self.gateway_id = os.environ.get('GATEWAY_ID', '')
        self.lambda_arn = os.environ.get('LAMBDA_ARN', '')
    
    def get_lambda_arn(self, account_id: str) -> str:
        """Generate Lambda ARN"""
        if self.lambda_arn:
            return self.lambda_arn
        return f"arn:aws:lambda:{self.aws_region}:{account_id}:function:{self.lambda_function_name}"
    
    def validate(self) -> bool:
        """Validate required configuration"""
        if not self.aws_region:
            raise ValueError("AWS_REGION is required")
        if not self.default_kb_id:
            raise ValueError("KNOWLEDGE_BASE_ID is required")
        return True

# Global config instance
config = Config()
