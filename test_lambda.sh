#!/bin/bash
# Test script for Lambda function

set -e

# Load configuration
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

REGION=${AWS_REGION:-us-east-1}
FUNCTION_NAME=${LAMBDA_FUNCTION_NAME:-BedrockKBMCPProxy}

echo "=== Testing Lambda Function ==="
echo "Function: $FUNCTION_NAME"
echo "Region: $REGION"
echo ""

# Test 1: List Knowledge Bases
echo "[Test 1] ListKnowledgeBases"
aws lambda invoke \
  --function-name $FUNCTION_NAME \
  --payload '{}' \
  --region $REGION \
  /tmp/test_list.json > /dev/null

echo "Response:"
cat /tmp/test_list.json | python3 -m json.tool
echo ""

# Test 2: Query Knowledge Base
echo "[Test 2] QueryKnowledgeBases"
aws lambda invoke \
  --function-name $FUNCTION_NAME \
  --payload '{"query":"test query","number_of_results":5}' \
  --region $REGION \
  /tmp/test_query.json > /dev/null

echo "Response:"
cat /tmp/test_query.json | python3 -m json.tool
echo ""

# Test 3: Query with specific KB ID
if [ -n "$KNOWLEDGE_BASE_ID" ]; then
    echo "[Test 3] QueryKnowledgeBases with specific KB ID"
    aws lambda invoke \
      --function-name $FUNCTION_NAME \
      --payload "{\"query\":\"test\",\"knowledge_base_id\":\"$KNOWLEDGE_BASE_ID\"}" \
      --region $REGION \
      /tmp/test_query_kb.json > /dev/null
    
    echo "Response:"
    cat /tmp/test_query_kb.json | python3 -m json.tool
    echo ""
fi

echo "=== Tests Complete ==="
