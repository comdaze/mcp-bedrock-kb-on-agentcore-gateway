#!/bin/bash
set -e

# ============================================
# Bedrock KB MCP Server - 一键部署脚本
# ============================================

echo "╔════════════════════════════════════════════════════════════╗"
echo "║   Bedrock Knowledge Base MCP Server - 一键部署             ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查 .env 文件
if [ ! -f .env ]; then
    echo -e "${RED}✗ 错误: .env 文件不存在${NC}"
    echo "请先复制 .env.example 到 .env 并配置必需的变量："
    echo "  cp .env.example .env"
    echo "  vim .env"
    exit 1
fi

# 加载环境变量
echo -e "${BLUE}[1/8]${NC} 加载配置..."
export $(cat .env | grep -v '^#' | grep -v '^$' | xargs)

# 验证必需的环境变量
if [ -z "$KNOWLEDGE_BASE_ID" ] || [ "$KNOWLEDGE_BASE_ID" = "your-knowledge-base-id-here" ]; then
    echo -e "${RED}✗ 错误: KNOWLEDGE_BASE_ID 未配置${NC}"
    echo "请在 .env 文件中设置 KNOWLEDGE_BASE_ID"
    exit 1
fi

if [ -z "$AWS_REGION" ]; then
    echo -e "${RED}✗ 错误: AWS_REGION 未配置${NC}"
    exit 1
fi

# 生成随机后缀（用于新部署）
RANDOM_SUFFIX=$(date +%s | tail -c 5)

# 设置默认值（如果未在 .env 中指定，则使用随机名称）
LAMBDA_FUNCTION_NAME=${LAMBDA_FUNCTION_NAME:-BedrockKBMCPProxy-${RANDOM_SUFFIX}}
LAMBDA_ROLE_NAME=${LAMBDA_ROLE_NAME:-BedrockKBMCPLambdaRole-${RANDOM_SUFFIX}}
KB_INCLUSION_TAG_KEY=${KB_INCLUSION_TAG_KEY:-mcp-multirag-kb}
KB_TAG_VALUE=${KB_TAG_VALUE:-true}
COGNITO_USER_POOL_NAME=${COGNITO_USER_POOL_NAME:-bedrock-kb-mcp-pool-${RANDOM_SUFFIX}}
COGNITO_USERNAME=${COGNITO_USERNAME:-admin}

echo -e "${GREEN}✓${NC} 配置加载完成"
echo "  - Knowledge Base ID: $KNOWLEDGE_BASE_ID"
echo "  - AWS Region: $AWS_REGION"
echo "  - Lambda Function: $LAMBDA_FUNCTION_NAME"
echo ""

# 检查依赖
echo -e "${BLUE}[2/8]${NC} 检查依赖..."
command -v aws >/dev/null 2>&1 || { echo -e "${RED}✗ 需要 AWS CLI${NC}"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo -e "${RED}✗ 需要 Python 3${NC}"; exit 1; }
command -v zip >/dev/null 2>&1 || { echo -e "${RED}✗ 需要 zip${NC}"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo -e "${YELLOW}⚠ 建议安装 jq 以获得更好的输出格式${NC}"; }
echo -e "${GREEN}✓${NC} 依赖检查完成"
echo ""

# 获取账户信息
echo -e "${BLUE}[3/8]${NC} 获取 AWS 账户信息..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}✗ 无法获取 AWS 账户 ID，请检查 AWS CLI 配置${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} AWS Account ID: $ACCOUNT_ID"
echo ""

# 创建 IAM 角色
echo -e "${BLUE}[4/8]${NC} 创建 IAM 角色..."
if aws iam get-role --role-name $LAMBDA_ROLE_NAME 2>/dev/null >/dev/null; then
    echo -e "${YELLOW}⚠${NC} IAM 角色已存在，跳过创建"
else
    cat > /tmp/trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "lambda.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF
    
    aws iam create-role \
      --role-name $LAMBDA_ROLE_NAME \
      --assume-role-policy-document file:///tmp/trust-policy.json \
      >/dev/null
    
    aws iam attach-role-policy \
      --role-name $LAMBDA_ROLE_NAME \
      --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
      >/dev/null
    
    cat > /tmp/bedrock-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "bedrock-agent:ListKnowledgeBases",
      "bedrock-agent:GetKnowledgeBase",
      "bedrock-agent:ListDataSources",
      "bedrock-agent-runtime:Retrieve",
      "bedrock:Retrieve"
    ],
    "Resource": "*"
  }]
}
EOF
    
    aws iam put-role-policy \
      --role-name $LAMBDA_ROLE_NAME \
      --policy-name BedrockKBAccess \
      --policy-document file:///tmp/bedrock-policy.json \
      >/dev/null
    
    echo -e "${GREEN}✓${NC} IAM 角色创建完成"
    echo "  等待 IAM 角色生效..."
    sleep 10
fi

LAMBDA_ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$LAMBDA_ROLE_NAME"
echo ""

# 部署 Lambda 函数
echo -e "${BLUE}[5/8]${NC} 部署 Lambda 函数..."
zip -q -j lambda_proxy.zip lambda_proxy.py

if aws lambda get-function --function-name $LAMBDA_FUNCTION_NAME --region $AWS_REGION 2>/dev/null >/dev/null; then
    echo -e "${YELLOW}⚠${NC} Lambda 函数已存在，更新代码..."
    aws lambda update-function-code \
      --function-name $LAMBDA_FUNCTION_NAME \
      --zip-file fileb://lambda_proxy.zip \
      --region $AWS_REGION \
      >/dev/null
    
    aws lambda update-function-configuration \
      --function-name $LAMBDA_FUNCTION_NAME \
      --environment "Variables={BEDROCK_REGION=$AWS_REGION,KNOWLEDGE_BASE_ID=$KNOWLEDGE_BASE_ID,KB_INCLUSION_TAG_KEY=$KB_INCLUSION_TAG_KEY,KB_TAG_VALUE=$KB_TAG_VALUE}" \
      --region $AWS_REGION \
      >/dev/null
    
    echo -e "${GREEN}✓${NC} Lambda 函数更新完成"
else
    aws lambda create-function \
      --function-name $LAMBDA_FUNCTION_NAME \
      --runtime python3.12 \
      --role $LAMBDA_ROLE_ARN \
      --handler lambda_proxy.lambda_handler \
      --zip-file fileb://lambda_proxy.zip \
      --timeout 60 \
      --memory-size 256 \
      --environment "Variables={BEDROCK_REGION=$AWS_REGION,KNOWLEDGE_BASE_ID=$KNOWLEDGE_BASE_ID,KB_INCLUSION_TAG_KEY=$KB_INCLUSION_TAG_KEY,KB_TAG_VALUE=$KB_TAG_VALUE}" \
      --region $AWS_REGION \
      >/dev/null
    
    echo -e "${GREEN}✓${NC} Lambda 函数创建完成"
fi

LAMBDA_ARN="arn:aws:lambda:$AWS_REGION:$ACCOUNT_ID:function:$LAMBDA_FUNCTION_NAME"
echo ""

# 创建 Cognito User Pool（用于 OAuth 认证）
echo -e "${BLUE}[6/8]${NC} 配置 Cognito 认证..."

# 检查是否已有 User Pool
EXISTING_POOL_ID=$(aws cognito-idp list-user-pools --max-results 60 --region $AWS_REGION \
  --query "UserPools[?Name=='$COGNITO_USER_POOL_NAME'].Id" --output text 2>/dev/null || echo "")

if [ -n "$EXISTING_POOL_ID" ]; then
    echo -e "${YELLOW}⚠${NC} Cognito User Pool 已存在: $EXISTING_POOL_ID"
    USER_POOL_ID=$EXISTING_POOL_ID
else
    echo "  创建 Cognito User Pool..."
    USER_POOL_ID=$(aws cognito-idp create-user-pool \
      --pool-name $COGNITO_USER_POOL_NAME \
      --policies "PasswordPolicy={MinimumLength=8,RequireUppercase=true,RequireLowercase=true,RequireNumbers=true,RequireSymbols=false}" \
      --region $AWS_REGION \
      --query 'UserPool.Id' \
      --output text)
    echo -e "${GREEN}✓${NC} User Pool 创建完成: $USER_POOL_ID"
fi

# 创建 User Pool Domain（使用随机后缀避免冲突）
COGNITO_DOMAIN="bedrock-kb-mcp-${RANDOM_SUFFIX}"
aws cognito-idp create-user-pool-domain \
  --domain $COGNITO_DOMAIN \
  --user-pool-id $USER_POOL_ID \
  --region $AWS_REGION \
  2>/dev/null || echo -e "${YELLOW}⚠${NC} Domain 可能已存在"

# 创建 Resource Server（必须在 App Client 之前）
echo "  创建 Resource Server..."
aws cognito-idp create-resource-server \
  --user-pool-id $USER_POOL_ID \
  --identifier "bedrock-kb-mcp" \
  --name "MCP Server" \
  --scopes ScopeName=mcp.read,ScopeDescription="Read access" ScopeName=mcp.write,ScopeDescription="Write access" \
  --region $AWS_REGION \
  2>/dev/null || echo -e "${YELLOW}⚠${NC} Resource Server 可能已存在"

# 创建 App Client
CLIENT_NAME="bedrock-kb-mcp-client"
EXISTING_CLIENT=$(aws cognito-idp list-user-pool-clients \
  --user-pool-id $USER_POOL_ID \
  --region $AWS_REGION \
  --query "UserPoolClients[?ClientName=='$CLIENT_NAME'].ClientId" \
  --output text 2>/dev/null || echo "")

if [ -n "$EXISTING_CLIENT" ]; then
    echo -e "${YELLOW}⚠${NC} App Client 已存在"
    CLIENT_ID=$EXISTING_CLIENT
    # 获取现有 client secret
    CLIENT_SECRET=$(aws cognito-idp describe-user-pool-client \
      --user-pool-id $USER_POOL_ID \
      --client-id $CLIENT_ID \
      --region $AWS_REGION \
      --query 'UserPoolClient.ClientSecret' \
      --output text 2>/dev/null || echo "")
else
    echo "  创建 App Client..."
    CLIENT_OUTPUT=$(aws cognito-idp create-user-pool-client \
      --user-pool-id $USER_POOL_ID \
      --client-name $CLIENT_NAME \
      --generate-secret \
      --allowed-o-auth-flows client_credentials \
      --allowed-o-auth-scopes "bedrock-kb-mcp/mcp.read" "bedrock-kb-mcp/mcp.write" \
      --allowed-o-auth-flows-user-pool-client \
      --region $AWS_REGION \
      --output json)
    
    CLIENT_ID=$(echo $CLIENT_OUTPUT | python3 -c "import sys, json; print(json.load(sys.stdin)['UserPoolClient']['ClientId'])")
    CLIENT_SECRET=$(echo $CLIENT_OUTPUT | python3 -c "import sys, json; print(json.load(sys.stdin)['UserPoolClient']['ClientSecret'])")
    echo -e "${GREEN}✓${NC} App Client 创建完成"
fi

TOKEN_ENDPOINT="https://$COGNITO_DOMAIN.auth.$AWS_REGION.amazoncognito.com/oauth2/token"

echo -e "${GREEN}✓${NC} Cognito 配置完成"
echo ""

# 创建 Gateway
echo -e "${BLUE}[7/8]${NC} 创建 AgentCore Gateway..."

if [ -n "$GATEWAY_ID" ]; then
    echo -e "${YELLOW}⚠${NC} 使用现有 Gateway: $GATEWAY_ID"
    GATEWAY_URL="https://$GATEWAY_ID.gateway.bedrock-agentcore.$AWS_REGION.amazonaws.com/mcp"
else
    GATEWAY_NAME="bedrock-kb-mcp-gw-${RANDOM_SUFFIX}"
    export GATEWAY_NAME=$GATEWAY_NAME
    export USER_POOL_ID=$USER_POOL_ID
    export CLIENT_ID=$CLIENT_ID
    
    GATEWAY_OUTPUT=$(python3 create_gateway.py 2>&1)
    echo "$GATEWAY_OUTPUT" | grep -E "✓|✗|⚠"
    
    GATEWAY_ID=$(echo "$GATEWAY_OUTPUT" | grep "^GATEWAY_ID=" | cut -d= -f2)
    GATEWAY_URL=$(echo "$GATEWAY_OUTPUT" | grep "^GATEWAY_URL=" | cut -d= -f2)
fi

if [ -n "$GATEWAY_ID" ] && [ "$GATEWAY_ID" != "N/A" ]; then
    echo -e "${GREEN}✓${NC} Gateway 配置完成"
    
    # 添加 Gateway Targets
    echo "  添加 Gateway Targets..."
    export GATEWAY_ID=$GATEWAY_ID
    export LAMBDA_ARN=$LAMBDA_ARN
    python3 add_gateway_target.py 2>&1 | grep -E "✓|✗" || true
else
    echo -e "${RED}✗${NC} Gateway 创建失败"
    GATEWAY_URL="N/A"
fi
echo ""

# 保存配置到 .env
echo -e "${BLUE}[8/8]${NC} 保存配置..."

# 更新 .env 文件
if ! grep -q "^LAMBDA_ARN=" .env 2>/dev/null; then
    echo "LAMBDA_ARN=$LAMBDA_ARN" >> .env
else
    sed -i.bak "s|^LAMBDA_ARN=.*|LAMBDA_ARN=$LAMBDA_ARN|" .env
fi

if [ -n "$GATEWAY_ID" ]; then
    if ! grep -q "^GATEWAY_ID=" .env 2>/dev/null; then
        echo "GATEWAY_ID=$GATEWAY_ID" >> .env
    else
        sed -i.bak "s|^GATEWAY_ID=.*|GATEWAY_ID=$GATEWAY_ID|" .env
    fi
fi

if [ -n "$GATEWAY_URL" ]; then
    if ! grep -q "^GATEWAY_URL=" .env 2>/dev/null; then
        echo "GATEWAY_URL=$GATEWAY_URL" >> .env
    else
        sed -i.bak "s|^GATEWAY_URL=.*|GATEWAY_URL=$GATEWAY_URL|" .env
    fi
fi

if ! grep -q "^COGNITO_USER_POOL_ID=" .env 2>/dev/null; then
    echo "COGNITO_USER_POOL_ID=$USER_POOL_ID" >> .env
else
    sed -i.bak "s|^COGNITO_USER_POOL_ID=.*|COGNITO_USER_POOL_ID=$USER_POOL_ID|" .env
fi

if ! grep -q "^COGNITO_CLIENT_ID=" .env 2>/dev/null; then
    echo "COGNITO_CLIENT_ID=$CLIENT_ID" >> .env
else
    sed -i.bak "s|^COGNITO_CLIENT_ID=.*|COGNITO_CLIENT_ID=$CLIENT_ID|" .env
fi

if ! grep -q "^COGNITO_CLIENT_SECRET=" .env 2>/dev/null; then
    echo "COGNITO_CLIENT_SECRET=$CLIENT_SECRET" >> .env
else
    sed -i.bak "s|^COGNITO_CLIENT_SECRET=.*|COGNITO_CLIENT_SECRET=$CLIENT_SECRET|" .env
fi

if ! grep -q "^COGNITO_DOMAIN=" .env 2>/dev/null; then
    echo "COGNITO_DOMAIN=$COGNITO_DOMAIN" >> .env
else
    sed -i.bak "s|^COGNITO_DOMAIN=.*|COGNITO_DOMAIN=$COGNITO_DOMAIN|" .env
fi

if ! grep -q "^TOKEN_ENDPOINT=" .env 2>/dev/null; then
    echo "TOKEN_ENDPOINT=$TOKEN_ENDPOINT" >> .env
else
    sed -i.bak "s|^TOKEN_ENDPOINT=.*|TOKEN_ENDPOINT=$TOKEN_ENDPOINT|" .env
fi

# 清理备份文件
rm -f .env.bak

echo -e "${GREEN}✓${NC} 配置已保存到 .env 文件"
echo ""

# 输出部署信息
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                    🎉 部署成功！                           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}📋 MCP Server 配置信息${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}【Lambda 函数信息】${NC}"
echo "  Function Name: $LAMBDA_FUNCTION_NAME"
echo "  Function ARN:  $LAMBDA_ARN"
echo "  Region:        $AWS_REGION"
echo ""
if [ -n "$GATEWAY_ID" ] && [ "$GATEWAY_ID" != "N/A" ]; then
echo -e "${YELLOW}【🌐 Gateway Endpoint (Quick Suite 配置用)】${NC}"
echo -e "  ${GREEN}Gateway ID:${NC}  $GATEWAY_ID"
echo -e "  ${GREEN}Gateway URL:${NC} $GATEWAY_URL"
echo ""
fi
echo -e "${YELLOW}【OAuth 认证信息】${NC}"
echo "  Token Endpoint: $TOKEN_ENDPOINT"
echo "  Client ID:      $CLIENT_ID"
echo "  Client Secret:  $CLIENT_SECRET"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🔧 Quick Suite 配置步骤${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "1. 登录 Amazon Quick Suite 控制台"
echo ""
echo "2. 创建 MCP Integration："
echo "   - Name: Bedrock Knowledge Base MCP"
echo "   - Description: Amazon Bedrock Knowledge Base integration"
echo ""
echo "3. 配置连接："
if [ -n "$GATEWAY_ID" ] && [ "$GATEWAY_ID" != "N/A" ]; then
echo -e "   - ${GREEN}MCP Server Endpoint:${NC} $GATEWAY_URL"
else
echo "   - MCP Server Endpoint: (需要手动创建 Gateway)"
fi
echo "   - Authentication Type: Service-to-service OAuth"
echo "   - Client ID: $CLIENT_ID"
echo "   - Client Secret: $CLIENT_SECRET"
echo "   - Token URL: $TOKEN_ENDPOINT"
echo "   - Connection purpose: Automated workflows"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🧪 测试命令${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "测试 Lambda 函数："
echo "  aws lambda invoke \\"
echo "    --function-name $LAMBDA_FUNCTION_NAME \\"
echo "    --payload '{\"query\":\"What is AWS?\"}' \\"
echo "    --region $AWS_REGION \\"
echo "    /tmp/response.json"
echo ""
echo "或运行测试脚本："
echo "  ./test_lambda.sh"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}💾 配置信息已保存到以下文件：${NC}"
echo "  - .env (环境变量)"
echo ""
echo -e "${YELLOW}⚠️  重要提示：${NC}"
echo "  - 请妥善保管 Client Secret，不要提交到代码仓库"
echo "  - .env 文件已添加到 .gitignore"
echo "  - 如需重新部署，直接运行 ./deploy_all.sh"
echo ""
echo -e "${GREEN}✨ 部署完成！祝使用愉快！${NC}"
echo ""
