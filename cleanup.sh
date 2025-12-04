#!/bin/bash
set -e

# ============================================
# 一键清理 Bedrock KB MCP Server 部署资源
# ============================================

echo "╔════════════════════════════════════════════════════════════╗"
echo "║   清理 Bedrock KB MCP Server 部署资源                     ║"
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
    echo "没有找到部署配置，无法清理"
    exit 1
fi

# 加载环境变量
echo -e "${BLUE}[1/6]${NC} 加载配置..."
export $(cat .env | grep -v '^#' | grep -v '^$' | xargs)

if [ -z "$AWS_REGION" ]; then
    AWS_REGION="us-east-1"
fi

echo -e "${GREEN}✓${NC} 配置加载完成"
echo "  - Region: $AWS_REGION"
echo ""

# 确认删除
echo -e "${YELLOW}⚠️  警告: 即将删除以下资源:${NC}"
echo ""
[ -n "$LAMBDA_ARN" ] && echo "  - Lambda 函数: $(basename $LAMBDA_ARN)"
[ -n "$GATEWAY_ID" ] && echo "  - Gateway: $GATEWAY_ID"
[ -n "$COGNITO_USER_POOL_ID" ] && echo "  - Cognito User Pool: $COGNITO_USER_POOL_ID"
echo "  - IAM 角色和策略"
echo ""
read -p "确认删除? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo -e "${YELLOW}取消清理${NC}"
    exit 0
fi

echo ""

# 1. 删除 Gateway Target
if [ -n "$GATEWAY_ID" ]; then
    echo -e "${BLUE}[2/6]${NC} 删除 Gateway Targets..."
    TARGETS=$(aws bedrock-agentcore-control list-gateway-targets \
        --gateway-identifier $GATEWAY_ID \
        --region $AWS_REGION \
        --query 'items[*].targetId' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$TARGETS" ]; then
        for TARGET_ID in $TARGETS; do
            echo "  删除 Target: $TARGET_ID"
            aws bedrock-agentcore-control delete-gateway-target \
                --gateway-identifier $GATEWAY_ID \
                --target-id $TARGET_ID \
                --region $AWS_REGION 2>/dev/null || true
        done
        echo -e "${GREEN}✓${NC} Gateway Targets 删除请求已发送"
        echo "  等待 Targets 删除完成..."
        sleep 10
        echo -e "${GREEN}✓${NC} Gateway Targets 删除完成"
    else
        echo -e "${YELLOW}⚠${NC} 没有找到 Gateway Targets"
    fi
else
    echo -e "${BLUE}[2/6]${NC} 跳过 Gateway Targets (未配置)"
fi
echo ""

# 2. 删除 Gateway
if [ -n "$GATEWAY_ID" ]; then
    echo -e "${BLUE}[3/6]${NC} 删除 Gateway..."
    
    # 尝试删除 Gateway
    DELETE_RESULT=$(aws bedrock-agentcore-control delete-gateway \
        --gateway-identifier $GATEWAY_ID \
        --region $AWS_REGION 2>&1)
    
    if echo "$DELETE_RESULT" | grep -q "DELETING\|deleted"; then
        echo -e "${GREEN}✓${NC} Gateway 删除请求已发送"
        echo "  等待 Gateway 删除完成..."
        sleep 5
        echo -e "${GREEN}✓${NC} Gateway 删除完成"
    else
        echo -e "${YELLOW}⚠${NC} Gateway 删除失败: $DELETE_RESULT"
    fi
    
    # 删除 Gateway IAM 角色
    if [ -n "$GATEWAY_ID" ]; then
        GATEWAY_ROLE_NAME=$(echo $GATEWAY_ID | sed 's/gateway/role/g')
        echo "  删除 Gateway IAM 角色..."
        aws iam delete-role-policy \
            --role-name $GATEWAY_ROLE_NAME \
            --policy-name LambdaInvokePolicy 2>/dev/null || true
        aws iam delete-role \
            --role-name $GATEWAY_ROLE_NAME 2>/dev/null || true
    fi
else
    echo -e "${BLUE}[3/6]${NC} 跳过 Gateway (未配置)"
fi
echo ""

# 3. 删除 Cognito
if [ -n "$COGNITO_USER_POOL_ID" ]; then
    echo -e "${BLUE}[4/6]${NC} 删除 Cognito User Pool..."
    
    # 删除 Domain
    if [ -n "$COGNITO_DOMAIN" ]; then
        echo "  删除 Cognito Domain: $COGNITO_DOMAIN"
        aws cognito-idp delete-user-pool-domain \
            --domain $COGNITO_DOMAIN \
            --user-pool-id $COGNITO_USER_POOL_ID \
            --region $AWS_REGION 2>/dev/null || true
        sleep 3
    fi
    
    # 删除 User Pool
    echo "  删除 User Pool: $COGNITO_USER_POOL_ID"
    aws cognito-idp delete-user-pool \
        --user-pool-id $COGNITO_USER_POOL_ID \
        --region $AWS_REGION 2>/dev/null && \
        echo -e "${GREEN}✓${NC} Cognito User Pool 删除完成" || \
        echo -e "${YELLOW}⚠${NC} Cognito User Pool 删除失败或不存在"
else
    echo -e "${BLUE}[4/6]${NC} 跳过 Cognito (未配置)"
fi
echo ""

# 4. 删除 Lambda 函数
if [ -n "$LAMBDA_ARN" ]; then
    echo -e "${BLUE}[5/6]${NC} 删除 Lambda 函数..."
    LAMBDA_NAME=$(basename $LAMBDA_ARN)
    aws lambda delete-function \
        --function-name $LAMBDA_NAME \
        --region $AWS_REGION 2>/dev/null && \
        echo -e "${GREEN}✓${NC} Lambda 函数删除完成" || \
        echo -e "${YELLOW}⚠${NC} Lambda 函数删除失败或不存在"
else
    echo -e "${BLUE}[5/6]${NC} 跳过 Lambda (未配置)"
fi
echo ""

# 5. 删除 IAM 角色
echo -e "${BLUE}[6/6]${NC} 删除 IAM 角色..."

# 删除 Lambda IAM 角色
if [ -n "$LAMBDA_ARN" ]; then
    LAMBDA_NAME=$(basename $LAMBDA_ARN)
    LAMBDA_ROLE_NAME=$(echo $LAMBDA_NAME | sed 's/Proxy/LambdaRole/g')
    
    echo "  删除 Lambda IAM 角色: $LAMBDA_ROLE_NAME"
    aws iam delete-role-policy \
        --role-name $LAMBDA_ROLE_NAME \
        --policy-name BedrockKBAccess 2>/dev/null || true
    aws iam detach-role-policy \
        --role-name $LAMBDA_ROLE_NAME \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
    aws iam delete-role \
        --role-name $LAMBDA_ROLE_NAME 2>/dev/null || true
fi

echo -e "${GREEN}✓${NC} IAM 角色清理完成"
echo ""

# 6. 清理本地文件
echo -e "${BLUE}清理本地文件...${NC}"
rm -f lambda_proxy.zip
rm -f .env.bak
echo -e "${GREEN}✓${NC} 本地文件清理完成"
echo ""

# 完成
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                    🎉 清理完成！                           ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo -e "${YELLOW}提示:${NC}"
echo "  - .env 文件已保留，如需重新部署可直接运行 ./deploy_all.sh"
echo "  - 如需完全清理，请手动删除 .env 文件: rm .env"
echo ""
