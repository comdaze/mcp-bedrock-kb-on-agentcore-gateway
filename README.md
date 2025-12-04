# Bedrock Knowledge Base MCP Server

基于 AWS Bedrock Knowledge Base 的 MCP (Model Context Protocol) 服务器，用于与 Amazon Quick Suite 集成。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.12+](https://img.shields.io/badge/python-3.12+-blue.svg)](https://www.python.org/downloads/)
[![AWS](https://img.shields.io/badge/AWS-Bedrock-orange.svg)](https://aws.amazon.com/bedrock/)

## 📋 目录

- [功能特性](#功能特性)
- [架构](#架构)
- [快速开始](#快速开始)
- [详细配置](#详细配置)
- [可用工具](#可用工具)
- [Quick Suite 集成](#quick-suite-集成)
- [测试](#测试)
- [部署选项](#部署选项)
- [安全最佳实践](#安全最佳实践)
- [故障排查](#故障排查)
- [API 参考](#api-参考)
- [更新日志](#更新日志)
- [贡献指南](#贡献指南)

## 🚀 功能特性

- ✅ 查询 Bedrock Knowledge Base 使用自然语言
- ✅ 列出所有可用的 Knowledge Bases
- ✅ 支持 AgentCore Gateway 集成
- ✅ 支持 Quick Suite MCP Integration
- ✅ 环境变量配置管理
- ✅ 完整的错误处理和日志
- ✅ 类型安全的 Python 实现
- ✅ 自动化部署脚本

## 🏗️ 架构

```
Quick Suite / Client Application
           ↓
    MCP Integration
           ↓
  AgentCore Gateway
           ↓
  Lambda Function (BedrockKBMCPProxy)
           ↓
Bedrock Knowledge Base
```


## ⚡ 快速开始

### 前置条件

- AWS CLI 已安装并配置
- Python 3.12+
- 至少一个 Bedrock Knowledge Base
- 具有必要的 IAM 权限

### 3 分钟一键部署

```bash
# 1. 配置环境变量
cp .env.example .env
vim .env  # 设置 KNOWLEDGE_BASE_ID

# 2. 一键部署（自动创建所有资源）
./deploy_all.sh

# 3. 测试
./test_lambda.sh
```

### 最小配置

编辑 `.env` 文件：

```bash
KNOWLEDGE_BASE_ID=your-kb-id-here
AWS_REGION=us-east-1
```

### 部署完成后

部署脚本会自动输出 Quick Suite 配置信息：

```
【🌐 Gateway Endpoint (Quick Suite 配置用)】
  Gateway URL: https://xxx.gateway.bedrock-agentcore.us-east-1.amazonaws.com/mcp

【OAuth 认证信息】
  Token Endpoint: https://xxx.auth.us-east-1.amazoncognito.com/oauth2/token
  Client ID: xxx
  Client Secret: xxx
```

所有配置信息会自动保存到 `.env` 文件，随时可查看：

```bash
cat .env | grep -E "GATEWAY_URL|TOKEN_ENDPOINT|CLIENT"
```

### 清理资源

```bash
# 一键删除所有部署的资源
./cleanup.sh
```


## 🔧 详细配置

### 环境变量

| 变量名 | 说明 | 默认值 | 必需 |
|--------|------|--------|------|
| `KNOWLEDGE_BASE_ID` | 默认 Knowledge Base ID | - | ✅ |
| `AWS_REGION` | AWS 区域 | us-east-1 | ✅ |
| `KB_INCLUSION_TAG_KEY` | KB 过滤标签键 | mcp-multirag-kb | ❌ |
| `KB_TAG_VALUE` | KB 过滤标签值 | true | ❌ |
| `LAMBDA_FUNCTION_NAME` | Lambda 函数名 | 自动生成随机名称 | ❌ |
| `LAMBDA_ROLE_NAME` | Lambda IAM 角色名 | 自动生成随机名称 | ❌ |
| `GATEWAY_ID` | Gateway ID | 自动生成 | ❌ |
| `GATEWAY_URL` | Gateway 完整 URL | 自动生成 | ❌ |
| `TOKEN_ENDPOINT` | OAuth Token URL | 自动生成 | ❌ |
| `COGNITO_CLIENT_ID` | Cognito Client ID | 自动生成 | ❌ |
| `COGNITO_CLIENT_SECRET` | Cognito Client Secret | 自动生成 | ❌ |

**注意**：
- 如果不指定资源名称，`deploy_all.sh` 会自动生成带随机后缀的名称，避免冲突
- 所有自动生成的配置会保存到 `.env` 文件
- 如需更新现有 Lambda，在 `.env` 中指定 `LAMBDA_FUNCTION_NAME` 并使用 `update_lambda.sh`

### IAM 权限

Lambda 函数需要以下权限：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "bedrock-agent:ListKnowledgeBases",
        "bedrock-agent:GetKnowledgeBase",
        "bedrock-agent:ListDataSources",
        "bedrock-agent-runtime:Retrieve",
        "bedrock:Retrieve"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    }
  ]
}
```

### Knowledge Base 标签（可选）

为 Knowledge Base 添加标签以便过滤：

```bash
aws bedrock-agent tag-resource \
  --resource-arn arn:aws:bedrock:us-east-1:ACCOUNT:knowledge-base/KB_ID \
  --tags mcp-multirag-kb=true \
  --region us-east-1
```


## 🛠️ 可用工具

### 1. ListKnowledgeBases

列出所有可用的 Knowledge Bases 及其数据源。

**参数**: 无

**示例请求**:
```json
{
  "tool_name": "ListKnowledgeBases"
}
```

**返回格式**:
```json
{
  "knowledge_bases": [
    {
      "id": "KB_ID",
      "name": "KB Name",
      "description": "Description",
      "data_sources": [
        {
          "id": "DS_ID",
          "name": "Data Source Name",
          "status": "AVAILABLE"
        }
      ]
    }
  ]
}
```

### 2. QueryKnowledgeBases

使用自然语言查询 Knowledge Base。

**参数**:
- `query` (必需, string): 查询文本
- `knowledge_base_id` (可选, string): KB ID，默认使用环境变量中的 ID
- `number_of_results` (可选, integer): 返回结果数，默认 10，最大 100

**示例请求**:
```json
{
  "tool_name": "QueryKnowledgeBases",
  "query": "What is Amazon S3?",
  "number_of_results": 5
}
```

**返回格式**:
```json
{
  "query": "What is Amazon S3?",
  "knowledge_base_id": "KB_ID",
  "results": [
    {
      "content": "Amazon S3 is...",
      "score": 0.95,
      "location": {
        "s3Location": {
          "uri": "s3://bucket/key"
        }
      },
      "metadata": {}
    }
  ],
  "count": 5
}
```


## 🔗 Quick Suite 集成

### 步骤 1: 获取配置信息

部署完成后，从输出或 `.env` 文件获取以下信息：

```bash
# 查看配置
cat .env | grep -E "GATEWAY_URL|TOKEN_ENDPOINT|CLIENT"
```

你需要：
- **Gateway URL**: `GATEWAY_URL`
- **Client ID**: `COGNITO_CLIENT_ID`
- **Client Secret**: `COGNITO_CLIENT_SECRET`
- **Token URL**: `TOKEN_ENDPOINT`

### 步骤 2: 创建 MCP Integration

1. 登录 Amazon Quick Suite 控制台
2. 导航到 **Integrations** → **Actions** → **Model Context Protocol**
3. 点击 **"+"** 创建新的 Integration

### 步骤 3: 配置基本信息

**Name**: `Bedrock Knowledge Base MCP`

**Description** (重要！告诉 LLM 何时使用):
```
Amazon Bedrock Knowledge Base integration via MCP. Provides access to query 
knowledge bases using natural language. Use QueryKnowledgeBases when users 
need to search for information in the knowledge base.
```

### 步骤 4: 配置连接

使用从 `.env` 文件获取的信息：

**MCP Server Endpoint**: 使用 `GATEWAY_URL` 的值

**Authentication Type**: Service-to-service OAuth

**Client ID**: 使用 `COGNITO_CLIENT_ID` 的值

**Client Secret**: 使用 `COGNITO_CLIENT_SECRET` 的值

**Token URL**: 使用 `TOKEN_ENDPOINT` 的值

**Connection purpose**: Automated workflows

### 步骤 5: 在 Quick Flows 中使用

#### 方法 A: Application Actions 节点

```
1. Enter your input 节点
2. Application actions 节点
   - Connector: Bedrock Knowledge Base MCP
   - Type: QueryKnowledgeBases
   - Prompt: 使用知识库工具搜索：{{Enter your input}}
```

#### 方法 B: AI Response 节点（推荐）

```
1. Enter your input 节点
2. General knowledge 或 Chat agent 节点
   - Prompt: 使用可用的知识库工具回答用户问题：{{Enter your input}}
   - Actions: 启用 Bedrock Knowledge Base MCP Integration
   - Model: Claude 3.5 Sonnet 或其他支持工具调用的模型
```

### OAuth 认证配置

如果需要配置 Cognito OAuth，运行：

```bash
# 设置环境变量
export REGION=us-east-1
export USERNAME=your_username
export PASSWORD=your_password

# 运行 Cognito 设置脚本（如果有）
source setup_cognito.sh
```

认证信息会保存到 `cognito_config.txt`（已添加到 .gitignore）。


## 🧪 测试

### 自动化测试

```bash
# 运行完整测试套件
./test_lambda.sh
```

测试脚本会自动测试：
- ListKnowledgeBases 功能
- QueryKnowledgeBases 功能
- 带参数的查询

### 手动测试

#### 测试 Lambda 函数

```bash
# 测试列表功能
aws lambda invoke \
  --function-name BedrockKBMCPProxy \
  --payload '{}' \
  --region us-east-1 \
  /tmp/test_list.json

cat /tmp/test_list.json | python3 -m json.tool

# 测试查询功能
aws lambda invoke \
  --function-name BedrockKBMCPProxy \
  --payload '{"query":"What is S3?","number_of_results":5}' \
  --region us-east-1 \
  /tmp/test_query.json

cat /tmp/test_query.json | python3 -m json.tool
```

#### 测试 Gateway

```bash
# 使用 curl 测试（需要认证）
curl -X POST https://your-gateway-id.gateway.bedrock-agentcore.us-east-1.amazonaws.com/mcp \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "tools/call",
    "params": {
      "name": "QueryKnowledgeBases",
      "arguments": {
        "query": "What is S3?"
      }
    },
    "id": 1
  }'
```

### Python 客户端示例

```python
import boto3
import json

# 直接调用 Lambda
lambda_client = boto3.client('lambda', region_name='us-east-1')

response = lambda_client.invoke(
    FunctionName='BedrockKBMCPProxy',
    Payload=json.dumps({
        'query': 'What is Amazon S3?',
        'number_of_results': 5
    })
)

result = json.loads(response['Payload'].read())
print(json.dumps(result, indent=2))
```


## 📦 部署选项

### 选项 1: 一键部署（推荐）

使用 `deploy_all.sh` 完整部署所有资源：

```bash
./deploy_all.sh
```

部署脚本会自动：
1. 创建 IAM 角色和策略
2. 部署 Lambda 函数
3. 配置 Cognito OAuth
4. 创建 AgentCore Gateway
5. 添加 Gateway Targets
6. 输出完整配置信息

### 选项 2: 更新现有 Lambda

如果只需要更新 Lambda 代码：

```bash
# 在 .env 中指定要更新的函数名
LAMBDA_FUNCTION_NAME=BedrockKBMCPProxy

# 运行更新脚本
./update_lambda.sh
```

### 选项 3: 清理资源

一键删除所有部署的资源：

```bash
./cleanup.sh
```

清理脚本会删除：
- Gateway 和 Gateway Targets
- Cognito User Pool
- Lambda 函数
- IAM 角色和策略

### 脚本说明

| 脚本 | 用途 | 说明 |
|------|------|------|
| `deploy_all.sh` | 完整部署 | 创建所有资源（Lambda、Gateway、Cognito） |
| `update_lambda.sh` | 更新 Lambda | 只更新 Lambda 代码和配置 |
| `cleanup.sh` | 清理资源 | 删除所有部署的资源 |
| `create_gateway.py` | 创建 Gateway | 单独创建 Gateway（被 deploy_all.sh 调用） |
| `add_gateway_target.py` | 添加 Target | 添加 Gateway Target（被 deploy_all.sh 调用） |
| `update_gateway_target.py` | 更新 Target | 更新现有 Gateway Target |
| `test_lambda.sh` | 测试 | 测试 Lambda 函数 |
  --zip-file fileb://lambda_proxy.zip \
  --timeout 60 \
  --memory-size 256 \
  --environment "Variables={AWS_REGION=us-east-1,KNOWLEDGE_BASE_ID=your-kb-id}" \
  --region us-east-1
```

#### 步骤 3: 添加 Gateway Target

```bash
# 设置环境变量
export GATEWAY_ID=your-gateway-id
export LAMBDA_ARN=arn:aws:lambda:us-east-1:ACCOUNT_ID:function:BedrockKBMCPProxy

# 运行脚本
python3 add_gateway_target.py
```

### 更新部署

```bash
# 更新 Lambda 代码
zip -j lambda_proxy.zip lambda_proxy.py
aws lambda update-function-code \
  --function-name BedrockKBMCPProxy \
  --zip-file fileb://lambda_proxy.zip \
  --region us-east-1

# 更新环境变量
aws lambda update-function-configuration \
  --function-name BedrockKBMCPProxy \
  --environment "Variables={AWS_REGION=us-east-1,KNOWLEDGE_BASE_ID=new-kb-id}" \
  --region us-east-1

# 更新 Gateway Target
export GATEWAY_ID=your-gateway-id
export TARGET_ID=your-target-id
export LAMBDA_ARN=your-lambda-arn
export TOOL_NAME=QueryKnowledgeBases
python3 update_gateway_target.py
```


## 🔒 安全最佳实践

### 敏感信息管理

**不要提交到代码库**:
- `.env` - 环境变量配置
- `cognito_config.txt` - Cognito 认证信息
- `*.zip` - Lambda 部署包
- `*.log` - 日志文件

这些文件已添加到 `.gitignore`。

### 环境变量

✅ **好的做法**:
```bash
export KNOWLEDGE_BASE_ID=your-kb-id
export AWS_REGION=us-east-1
```

❌ **不好的做法**:
```python
# 不要在代码中硬编码
KNOWLEDGE_BASE_ID = "PTTWEFYB6R"
```

### IAM 权限最小化

只授予必需的权限，避免使用通配符：

```json
// ❌ 不好的做法
{
  "Effect": "Allow",
  "Action": "bedrock-agent:*",
  "Resource": "*"
}

// ✅ 好的做法
{
  "Effect": "Allow",
  "Action": [
    "bedrock-agent:ListKnowledgeBases",
    "bedrock-agent:GetKnowledgeBase"
  ],
  "Resource": "arn:aws:bedrock:us-east-1:123456789012:knowledge-base/*"
}
```

### 日志安全

不要记录敏感信息：

```python
# ❌ 不好的做法
print(f"Client Secret: {client_secret}")

# ✅ 好的做法
print(f"Authentication successful")
```

### 网络安全

- ✅ 始终使用 HTTPS
- ✅ 使用 OAuth 2.0 或 API Key 认证
- ❌ 不要使用无认证的公开端点

### 定期审计

- [ ] 检查 `.gitignore` 是否包含所有敏感文件
- [ ] 检查代码中是否有硬编码的密钥
- [ ] 检查 IAM 权限是否最小化
- [ ] 检查日志中是否包含敏感信息
- [ ] 定期轮换密钥和令牌

### 密钥泄露应急响应

如果密钥泄露：

1. **立即轮换密钥**
```bash
aws cognito-idp update-user-pool-client \
  --user-pool-id your-pool-id \
  --client-id your-client-id \
  --generate-secret
```

2. **撤销访问**
```bash
aws apigateway delete-api-key --api-key your-key-id
```

3. **审计日志**
```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=Username,AttributeValue=leaked-user
```


## 🔍 故障排查

### Lambda 函数错误

**查看日志**:
```bash
aws logs tail /aws/lambda/BedrockKBMCPProxy --follow --region us-east-1
```

**检查配置**:
```bash
aws lambda get-function-configuration \
  --function-name BedrockKBMCPProxy \
  --region us-east-1 \
  --query 'Environment.Variables'
```

**常见错误**:

| 错误 | 原因 | 解决方案 |
|------|------|----------|
| `AccessDeniedException` | IAM 权限不足 | 检查 Lambda 执行角色权限 |
| `ResourceNotFoundException` | KB ID 不存在 | 验证 KNOWLEDGE_BASE_ID |
| `ValidationException` | 参数格式错误 | 检查请求参数格式 |
| `ThrottlingException` | 请求过多 | 实施重试逻辑或增加配额 |

### Gateway 连接失败

**检查 Gateway 状态**:
```bash
aws bedrock-agent-runtime list-gateway-targets \
  --gateway-id your-gateway-id \
  --region us-east-1
```

**验证认证**:
```bash
# 测试获取 token
curl -X POST https://your-user-pool.auth.us-east-1.amazoncognito.com/oauth2/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=YOUR_CLIENT_ID&client_secret=YOUR_CLIENT_SECRET"
```

### Knowledge Base 未找到

**列出所有 KB**:
```bash
aws bedrock-agent list-knowledge-bases --region us-east-1
```

**检查 KB 详情**:
```bash
aws bedrock-agent get-knowledge-base \
  --knowledge-base-id your-kb-id \
  --region us-east-1
```

**检查标签**:
```bash
aws bedrock-agent list-tags-for-resource \
  --resource-arn arn:aws:bedrock:us-east-1:ACCOUNT:knowledge-base/KB_ID \
  --region us-east-1
```

### 部署失败

**检查 AWS CLI 配置**:
```bash
aws sts get-caller-identity
aws configure list
```

**检查权限**:
```bash
# 测试是否有创建 Lambda 的权限
aws lambda list-functions --region us-east-1

# 测试是否有 Bedrock 权限
aws bedrock-agent list-knowledge-bases --region us-east-1
```

### Quick Suite 集成问题

**Integration 状态为 "Unavailable"**:
- 检查 Gateway URL 是否正确
- 验证认证信息
- 确认 Token URL 正确

**看不到工具**:
- 确认 Gateway Target 已创建
- 等待 1-2 分钟让系统同步
- 检查 Lambda 函数是否正常运行

**查询返回错误**:
- 查看 Lambda 日志
- 验证 Knowledge Base ID
- 检查 Lambda 权限


## 📚 API 参考

### Lambda Handler 接口

```python
def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]
```

**输入格式**:

```json
{
  "tool_name": "QueryKnowledgeBases",  // 可选，显式指定工具
  "query": "查询文本",                  // QueryKnowledgeBases 必需
  "knowledge_base_id": "KB_ID",        // 可选，默认使用环境变量
  "number_of_results": 10              // 可选，默认 10
}
```

**输出格式**:

```json
{
  "statusCode": 200,
  "body": "{\"content\":[{\"type\":\"text\",\"text\":\"格式化的结果文本\"}]}"
}
```

### MCP 协议格式

**请求格式**:

```json
{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "params": {
    "name": "QueryKnowledgeBases",
    "arguments": {
      "query": "What is S3?",
      "number_of_results": 5
    }
  },
  "id": 1
}
```

**响应格式**:

```json
{
  "jsonrpc": "2.0",
  "result": {
    "content": [
      {
        "type": "text",
        "text": "# 知识库查询结果\n\n**查询**: What is S3?\n..."
      }
    ]
  },
  "id": 1
}
```

### 配置模块 API

```python
from config import Config

# 创建配置实例
config = Config()

# 验证配置
config.validate()

# 获取 Lambda ARN
lambda_arn = config.get_lambda_arn(account_id="123456789012")
```


## 📁 项目结构

```
bedrock-kb-mcp/
├── README.md                    # 完整文档
├── .env.example                 # 配置模板
├── .env                         # 配置（不提交）
├── .gitignore                   # Git 规则
├── requirements.txt             # 依赖
├── config.py                    # 配置模块
├── lambda_proxy.py              # Lambda 代码
├── deploy_all.sh                # 一键部署
├── cleanup.sh                   # 一键清理
├── update_lambda.sh             # 更新 Lambda
├── create_gateway.py            # 创建 Gateway
├── add_gateway_target.py        # 添加 Target
├── update_gateway_target.py     # 更新 Target
└── test_lambda.sh               # 测试脚本
```

## 🔄 更新日志

### [3.0.0] - 2024-12-04

**重大变更**:
- ✅ 完整的一键部署脚本 (`deploy_all.sh`)
- ✅ 自动创建 Gateway 和 Gateway Targets
- ✅ 自动配置 Cognito OAuth 认证
- ✅ 资源名称使用随机后缀避免冲突
- ✅ 修复 `AWS_REGION` 环境变量问题（改用 `BEDROCK_REGION`）

**新增功能**:
- ✅ `cleanup.sh` - 一键清理所有资源
- ✅ `update_lambda.sh` - 更新现有 Lambda
- ✅ `create_gateway.py` - 自动创建 Gateway
- ✅ 完整的 Gateway endpoint 输出
- ✅ 所有配置自动保存到 `.env` 文件

**修复**:
- ✅ Gateway Target API 参数格式
- ✅ Cognito Resource Server 配置顺序
- ✅ 添加 `bedrock:Retrieve` 权限
- ✅ Gateway 删除等待逻辑
- ✅ 完整文档整合
- ✅ 安全最佳实践
- ✅ 改进的错误处理

**修复**:
- ✅ 区域配置不一致
- ✅ 工具名称不匹配
- ✅ Lambda 函数逻辑问题
- ✅ 文档中的敏感信息

详细变更请查看 [CHANGELOG.md](CHANGELOG.md)。

### 从 1.0.0 升级

```bash
# 1. 更新环境变量名称
sed -i 's/DEFAULT_KB_ID/KNOWLEDGE_BASE_ID/g' .env
sed -i 's/KB_TAG_KEY/KB_INCLUSION_TAG_KEY/g' .env

# 2. 重新部署
./deploy.sh

# 3. 更新 Gateway Targets
export GATEWAY_ID=your-gateway-id
export TARGET_ID=your-target-id
export LAMBDA_ARN=your-lambda-arn
python3 update_gateway_target.py
```


## 🤝 贡献指南

### 开发环境设置

```bash
# 克隆项目
git clone <repository-url>
cd bedrock-kb-mcp

# 配置环境
cp .env.example .env
vim .env

# 安装依赖（用于本地开发）
pip install -r requirements.txt
```

### 代码规范

- 使用 Python 3.12+ 特性
- 添加类型注解
- 遵循 PEP 8 规范
- 编写清晰的文档字符串

### 提交前检查

```bash
# 1. 语法检查
python3 -m py_compile lambda_proxy.py config.py

# 2. 测试
./test_lambda.sh

# 3. 检查敏感信息
git diff --cached
```

### 提交规范

使用语义化提交消息：

```
feat: 添加新功能
fix: 修复 bug
docs: 更新文档
refactor: 重构代码
test: 添加测试
chore: 其他修改
```

## 📄 许可证

MIT License

Copyright (c) 2024

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


## 🔗 相关资源

### AWS 文档
- [Amazon Bedrock Documentation](https://docs.aws.amazon.com/bedrock/)
- [Bedrock Knowledge Bases](https://docs.aws.amazon.com/bedrock/latest/userguide/knowledge-base.html)
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)

### MCP 协议
- [Model Context Protocol](https://modelcontextprotocol.io/)
- [MCP Specification](https://spec.modelcontextprotocol.io/)

### Quick Suite
- [Amazon Quick Suite Documentation](https://aws.amazon.com/quicksuite/)

### 安全
- [AWS Security Best Practices](https://aws.amazon.com/security/best-practices/)
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [AWS Well-Architected Framework - Security Pillar](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/welcome.html)

## ❓ 常见问题

### Q: 支持哪些 AWS 区域？

A: 理论上支持所有有 Bedrock 服务的区域。默认使用 `us-east-1`，可以通过 `AWS_REGION` 环境变量修改。

### Q: 可以同时查询多个 Knowledge Bases 吗？

A: 当前版本每次查询一个 KB。可以通过 `knowledge_base_id` 参数指定不同的 KB，或者多次调用工具。

### Q: 如何提高查询性能？

A: 
- 优化 Knowledge Base 的数据源
- 调整 `number_of_results` 参数
- 使用更精确的查询语句
- 考虑添加缓存层

### Q: 支持流式响应吗？

A: 当前版本不支持流式响应。这是未来的改进方向。

### Q: 如何监控和告警？

A: 
- 使用 CloudWatch Logs 查看 Lambda 日志
- 配置 CloudWatch Alarms 监控错误率
- 使用 X-Ray 进行分布式追踪

### Q: 成本如何？

A: 主要成本来自：
- Lambda 调用次数和执行时间
- Bedrock Knowledge Base 查询次数
- CloudWatch Logs 存储
- Gateway 数据传输（如果使用）

建议使用 AWS Cost Explorer 监控实际成本。

### Q: 如何清理部署的资源？

A: 
```bash
# 删除 Lambda 函数
aws lambda delete-function --function-name BedrockKBMCPProxy --region us-east-1

# 删除 IAM 角色
aws iam delete-role-policy --role-name BedrockKBMCPLambdaRole --policy-name BedrockKBAccess
aws iam detach-role-policy --role-name BedrockKBMCPLambdaRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws iam delete-role --role-name BedrockKBMCPLambdaRole

# 删除 Gateway（如果创建了）
aws bedrock-agentcore-control delete-gateway --gateway-identifier your-gateway-id --region us-east-1
```

## 📞 支持

遇到问题？

1. 查看 [故障排查](#故障排查) 部分
2. 检查 [常见问题](#常见问题)
3. 查看 Lambda 日志获取详细错误信息
4. 提交 Issue 到项目仓库

## 🎯 路线图

### 短期 (1-2 周)
- [ ] 添加单元测试
- [ ] 添加集成测试
- [ ] 创建 CI/CD 流程
- [ ] 添加性能监控

### 中期 (1-2 月)
- [ ] 支持多个 Knowledge Bases 并行查询
- [ ] 添加缓存机制
- [ ] 改进错误重试逻辑
- [ ] 添加指标和告警

### 长期 (3-6 月)
- [ ] 支持流式响应
- [ ] 添加 Web UI
- [ ] 支持更多 MCP 功能
- [ ] 多区域部署支持

---

**Made with ❤️ for AWS Bedrock and MCP**

如果这个项目对你有帮助，请给个 ⭐️！
