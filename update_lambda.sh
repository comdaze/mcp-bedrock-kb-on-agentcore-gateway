#!/bin/bash
set -e

# ============================================
# 更新现有 Lambda 函数脚本
# ============================================

echo "╔════════════════════════════════════════════════════════════╗"
echo "║   更新 Bedrock KB MCP Lambda 函数                          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 检查 .env 文件
if [ ! -f .env ]; then
    echo -e "${RED}✗ 错误: .env 文件不存在${NC}"
    exit 1
fi

# 加载环境变量
echo -e "${BLUE}[1/4]${NC} 加载配置..."
export $(cat .env | grep -v '^#' | grep -v '^$' | xargs)

# 验证必需的环境变量
if [ -z "$KNOWLEDGE_BASE_ID" ]; then
    echo -e "${RED}✗ 错误: KNOWLEDGE_BASE_ID 未配置${NC}"
    exit 1
fi

if [ -z "$AWS_REGION" ]; then
    echo -e "${RED}✗ 错误: AWS_REGION 未配置${NC}"
    exit 1
fi

# Lambda 函数名称（必须指定要更新的函数）
if [ -z "$LAMBDA_FUNCTION_NAME" ]; then
    echo -e "${RED}✗ 错误: 请在 .env 中指定 LAMBDA_FUNCTION_NAME${NC}"
    echo "例如: LAMBDA_FUNCTION_NAME=BedrockKBMCPProxy"
    exit 1
fi

# 设置默认值
KB_INCLUSION_TAG_KEY=${KB_INCLUSION_TAG_KEY:-mcp-multirag-kb}
KB_TAG_VALUE=${KB_TAG_VALUE:-true}

echo -e "${GREEN}✓${NC} 配置加载完成"
echo "  - Lambda Function: $LAMBDA_FUNCTION_NAME"
echo "  - Knowledge Base ID: $KNOWLEDGE_BASE_ID"
echo "  - AWS Region: $AWS_REGION"
echo ""

# 检查 Lambda 函数是否存在
echo -e "${BLUE}[2/4]${NC} 检查 Lambda 函数..."
if ! aws lambda get-function --function-name $LAMBDA_FUNCTION_NAME --region $AWS_REGION 2>/dev/null >/dev/null; then
    echo -e "${RED}✗ 错误: Lambda 函数 '$LAMBDA_FUNCTION_NAME' 不存在${NC}"
    echo "请先运行 deploy_all.sh 创建函数，或检查函数名称是否正确"
    exit 1
fi
echo -e "${GREEN}✓${NC} Lambda 函数存在"

# 打包代码
echo -e "${BLUE}[3/4]${NC} 打包代码..."
rm -f lambda_proxy.zip
zip -q -j lambda_proxy.zip lambda_proxy.py
echo -e "${GREEN}✓${NC} 代码打包完成"

# 更新 Lambda 函数
echo -e "${BLUE}[4/4]${NC} 更新 Lambda 函数..."

# 更新代码
echo "  - 更新代码..."
aws lambda update-function-code \
  --function-name $LAMBDA_FUNCTION_NAME \
  --zip-file fileb://lambda_proxy.zip \
  --region $AWS_REGION \
  >/dev/null

# 等待代码更新完成
echo "  - 等待代码更新完成..."
aws lambda wait function-updated \
  --function-name $LAMBDA_FUNCTION_NAME \
  --region $AWS_REGION

# 更新环境变量
echo "  - 更新环境变量..."
aws lambda update-function-configuration \
  --function-name $LAMBDA_FUNCTION_NAME \
  --environment "Variables={BEDROCK_REGION=$AWS_REGION,KNOWLEDGE_BASE_ID=$KNOWLEDGE_BASE_ID,KB_INCLUSION_TAG_KEY=$KB_INCLUSION_TAG_KEY,KB_TAG_VALUE=$KB_TAG_VALUE}" \
  --region $AWS_REGION \
  >/dev/null

echo -e "${GREEN}✓${NC} Lambda 函数更新完成"
echo ""

# 清理
rm -f lambda_proxy.zip

# 获取函数信息
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
LAMBDA_ARN="arn:aws:lambda:$AWS_REGION:$ACCOUNT_ID:function:$LAMBDA_FUNCTION_NAME"

# 显示摘要
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                    更新完成                                ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo -e "${YELLOW}【Lambda 函数信息】${NC}"
echo "  Function Name: $LAMBDA_FUNCTION_NAME"
echo "  Function ARN:  $LAMBDA_ARN"
echo "  Region:        $AWS_REGION"
echo ""
echo -e "${YELLOW}【环境变量】${NC}"
echo "  BEDROCK_REGION:        $AWS_REGION"
echo "  KNOWLEDGE_BASE_ID:     $KNOWLEDGE_BASE_ID"
echo "  KB_INCLUSION_TAG_KEY:  $KB_INCLUSION_TAG_KEY"
echo "  KB_TAG_VALUE:          $KB_TAG_VALUE"
echo ""
echo -e "${YELLOW}【测试命令】${NC}"
echo "  ./test_lambda.sh"
echo ""
echo "或手动测试："
echo "  aws lambda invoke \\"
echo "    --function-name $LAMBDA_FUNCTION_NAME \\"
echo "    --payload '{\"query\":\"What is AWS?\"}' \\"
echo "    --region $AWS_REGION \\"
echo "    /tmp/response.json"
echo ""
