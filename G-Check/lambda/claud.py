import json
import boto3

br = boto3.client("bedrock-runtime")


def invoke_claude(model_id: str, system: str, user: str) -> str:
    """
    Invoke Claude via Amazon Bedrock.

    Args:
        model_id: Bedrock model ID (e.g., anthropic.claude-3-haiku-20240307-v1:0)
        system: System prompt to set Claude's behavior
        user: User message/question

    Returns:
        Claude's text response
    """
    body = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 2000,
        "temperature": 0.2,
        "system": system,
        "messages": [
            {"role": "user", "content": [{"type": "text", "text": user}]}
        ]
    }

    resp = br.invoke_model(
        modelId=model_id,
        contentType="application/json",
        accept="application/json",
        body=json.dumps(body),
    )
    payload = json.loads(resp["body"].read())
    # Claude responses contain "content" with text parts
    text_parts = payload.get("content", [])
    return "\n".join([p.get("text", "") for p in text_parts if p.get("type") == "text"])
