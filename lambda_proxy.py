"""
Lambda Proxy for Bedrock KB MCP Server
直接实现Knowledge Base查询功能
"""
import json
import boto3
import os
from typing import Dict, Any, List

# Configuration
REGION = os.environ.get('BEDROCK_REGION', os.environ.get('AWS_REGION', 'us-east-1'))
KB_TAG_KEY = os.environ.get('KB_INCLUSION_TAG_KEY', 'mcp-multirag-kb')
KB_TAG_VALUE = os.environ.get('KB_TAG_VALUE', 'true')
DEFAULT_KB_ID = os.environ.get('KNOWLEDGE_BASE_ID', 'PTTWEFYB6R')

# Initialize AWS clients
bedrock_agent = boto3.client('bedrock-agent', region_name=REGION)
bedrock_agent_runtime = boto3.client('bedrock-agent-runtime', region_name=REGION)

def list_knowledge_bases():
    """列出所有Knowledge Bases"""
    try:
        response = bedrock_agent.list_knowledge_bases(maxResults=100)
        kbs = []
        
        for kb in response.get('knowledgeBaseSummaries', []):
            kb_id = kb['knowledgeBaseId']
            
            # 获取数据源
            try:
                ds_response = bedrock_agent.list_data_sources(
                    knowledgeBaseId=kb_id,
                    maxResults=10
                )
                
                data_sources = [
                    {
                        'id': ds['dataSourceId'],
                        'name': ds['name'],
                        'status': ds['status']
                    }
                    for ds in ds_response.get('dataSourceSummaries', [])
                ]
            except Exception as e:
                print(f"Error getting data sources for KB {kb_id}: {e}")
                data_sources = []
            
            kbs.append({
                'id': kb_id,
                'name': kb['name'],
                'description': kb.get('description', ''),
                'data_sources': data_sources
            })
        
        return {'knowledge_bases': kbs}
    
    except Exception as e:
        raise Exception(f"Failed to list knowledge bases: {str(e)}")

def query_knowledge_base(query, knowledge_base_id, number_of_results=10):
    """查询Knowledge Base"""
    try:
        response = bedrock_agent_runtime.retrieve(
            knowledgeBaseId=knowledge_base_id,
            retrievalQuery={'text': query},
            retrievalConfiguration={
                'vectorSearchConfiguration': {
                    'numberOfResults': number_of_results
                }
            }
        )
        
        results = []
        for item in response.get('retrievalResults', []):
            results.append({
                'content': item['content']['text'],
                'score': item.get('score', 0),
                'location': item.get('location', {}),
                'metadata': item.get('metadata', {})
            })
        
        return {
            'query': query,
            'knowledge_base_id': knowledge_base_id,
            'results': results,
            'count': len(results)
        }
    
    except Exception as e:
        raise Exception(f"Failed to query knowledge base: {str(e)}")

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler - 支持多种调用方式
    1. Gateway 直接传递工具参数
    2. 显式指定 tool_name
    """
    try:
        print(f"Received event: {json.dumps(event)}")
        
        # 获取工具名称（如果提供）
        tool_name = event.get('tool_name', '')
        
        # 根据工具名称或参数判断调用哪个功能
        if tool_name == 'ListKnowledgeBases' or (not tool_name and 'query' not in event):
            # ListKnowledgeBases
            result = list_knowledge_bases()
            formatted_text = format_list_results(result)
            
        elif tool_name == 'QueryKnowledgeBases' or 'query' in event:
            # QueryKnowledgeBases
            if 'query' not in event:
                raise ValueError("Missing required parameter: query")
            
            kb_id = event.get('knowledge_base_id') or DEFAULT_KB_ID
            number_of_results = event.get('number_of_results', 10)
            
            result = query_knowledge_base(event['query'], kb_id, number_of_results)
            formatted_text = format_query_results(result)
            
        else:
            raise ValueError(f"Unknown tool or invalid parameters. Tool: {tool_name}, Event: {event}")
        
        print(f"Result: {json.dumps(result, default=str)}")
        
        # 返回 MCP 标准格式
        return {
            'statusCode': 200,
            'body': json.dumps({
                'content': [
                    {
                        'type': 'text',
                        'text': formatted_text
                    }
                ]
            })
        }
        
    except Exception as e:
        error_msg = str(e)
        print(f"Error: {error_msg}")
        import traceback
        traceback.print_exc()
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'content': [
                    {
                        'type': 'text',
                        'text': f'错误: {error_msg}'
                    }
                ]
            })
        }

def format_query_results(result: Dict[str, Any]) -> str:
    """格式化查询结果为可读文本"""
    query = result.get('query', '')
    kb_id = result.get('knowledge_base_id', '')
    results = result.get('results', [])
    count = result.get('count', 0)
    
    text = f"# 知识库查询结果\n\n"
    text += f"**查询**: {query}\n"
    text += f"**知识库ID**: {kb_id}\n"
    text += f"**结果数量**: {count}\n\n"
    
    if not results:
        text += "未找到相关结果。\n"
        return text
    
    for idx, item in enumerate(results, 1):
        content = item.get('content', '无内容')
        score = item.get('score', 0)
        location = item.get('location', {})
        
        text += f"## 结果 {idx} (相关度: {score:.4f})\n\n"
        text += f"{content}\n\n"
        
        # 添加来源信息
        if location:
            s3_location = location.get('s3Location', {})
            if s3_location:
                text += f"**来源**: {s3_location.get('uri', '未知')}\n\n"
        
        text += "---\n\n"
    
    return text

def format_list_results(result: Dict[str, Any]) -> str:
    """格式化知识库列表为可读文本"""
    kbs = result.get('knowledge_bases', [])
    count = len(kbs)
    
    text = f"# 可用知识库列表\n\n"
    text += f"共找到 {count} 个知识库\n\n"
    
    if not kbs:
        text += "未找到任何知识库。\n"
        return text
    
    for idx, kb in enumerate(kbs, 1):
        kb_id = kb.get('id', '未知')
        name = kb.get('name', '未命名')
        description = kb.get('description', '无描述')
        data_sources = kb.get('data_sources', [])
        
        text += f"## {idx}. {name}\n\n"
        text += f"**ID**: {kb_id}\n"
        text += f"**描述**: {description}\n"
        
        if data_sources:
            text += f"**数据源** ({len(data_sources)}):\n"
            for ds in data_sources:
                text += f"  - {ds.get('name', '未命名')} (状态: {ds.get('status', '未知')})\n"
        
        text += "\n"
    
    return text
