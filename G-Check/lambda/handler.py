import os, json, time, datetime
import boto3

logs = boto3.client("logs")
ssm = boto3.client("ssm")
secrets = boto3.client("secretsmanager")
s3 = boto3.client("s3")
sns = boto3.client("sns")
bedrock = boto3.client("bedrock-runtime")

REPORT_BUCKET = os.environ["REPORT_BUCKET"]
APP_LOG_GROUP = os.environ["APP_LOG_GROUP"]
WAF_LOG_GROUP = os.environ.get("WAF_LOG_GROUP", "")
SECRET_ID = os.environ["SECRET_ID"]
SSM_PARAM_PATH = os.environ["SSM_PARAM_PATH"]
MODEL_ID = os.environ["BEDROCK_MODEL_ID"]
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]


def run_insights_query(log_group: str, query: str, start_ts: int, end_ts: int, limit=100):
    """Run CloudWatch Logs Insights query and wait for results."""
    if not log_group:
        return {"status": "Skipped", "results": []}

    try:
        qid = logs.start_query(
            logGroupName=log_group,
            startTime=start_ts,
            endTime=end_ts,
            queryString=query,
            limit=limit
        )["queryId"]

        # Poll until complete
        for _ in range(20):
            resp = logs.get_query_results(queryId=qid)
            status = resp.get("status")
            if status in ("Complete", "Failed", "Cancelled", "Timeout"):
                return {"status": status, "results": resp.get("results", [])}
            time.sleep(1.0)

        return {"status": "Timeout", "results": []}
    except Exception as e:
        return {"status": "Error", "error": str(e), "results": []}


def get_params_by_path(path: str):
    """Retrieve all SSM parameters under a path."""
    out = {}
    try:
        next_token = None
        while True:
            kwargs = {"Path": path, "Recursive": True, "WithDecryption": True}
            if next_token:
                kwargs["NextToken"] = next_token
            resp = ssm.get_parameters_by_path(**kwargs)
            for p in resp.get("Parameters", []):
                out[p["Name"]] = p["Value"]
            next_token = resp.get("NextToken")
            if not next_token:
                break
    except Exception as e:
        out["_error"] = str(e)
    return out


def get_secret(secret_id: str):
    """Retrieve secret metadata (excluding password)."""
    try:
        s = secrets.get_secret_value(SecretId=secret_id)["SecretString"]
        return json.loads(s)
    except Exception as e:
        return {"_error": str(e)}


def bedrock_generate(report_prompt: str):
    """Generate report using Bedrock Claude model."""
    # Claude Messages API format for Bedrock
    body = json.dumps({
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 4000,
        "temperature": 0.2,
        "messages": [
            {"role": "user", "content": [{"type": "text", "text": report_prompt}]}
        ]
    })

    try:
        resp = bedrock.invoke_model(
            modelId=MODEL_ID,
            contentType="application/json",
            accept="application/json",
            body=body
        )
        payload = json.loads(resp["body"].read())
        # Extract text from Claude response
        content = payload.get("content", [])
        text_parts = [p.get("text", "") for p in content if p.get("type") == "text"]
        return "\n".join(text_parts)
    except Exception as e:
        return f"# Error generating report\n\nBedrock error: {str(e)}"


def lambda_handler(event, context):
    """Main Lambda handler for incident reporting."""
    now = int(time.time())
    end_ts = now
    start_ts = now - 15 * 60  # 15 min "fast report" window

    print(f"Starting incident report generation: {datetime.datetime.utcnow().isoformat()}")
    print(f"Event: {json.dumps(event)}")

    # 1) Pull config sources
    params = get_params_by_path(SSM_PARAM_PATH)
    secret = get_secret(SECRET_ID)

    # 2) Run App + WAF queries (minimal pack)
    app_errors = run_insights_query(
        APP_LOG_GROUP,
        "fields @timestamp, @message | filter @message like /ERROR|DB|timeout|refused|Access denied/i | sort @timestamp desc | limit 50",
        start_ts, end_ts
    )
    app_rate = run_insights_query(
        APP_LOG_GROUP,
        "fields @timestamp, @message | filter @message like /ERROR|DB|timeout|refused|Access denied/i | stats count() as errors by bin(1m) | sort bin(1m) asc",
        start_ts, end_ts
    )

    # WAF queries (if WAF log group configured)
    waf_actions = run_insights_query(
        WAF_LOG_GROUP,
        "fields @timestamp, action | stats count() as hits by action | sort hits desc",
        start_ts, end_ts
    )
    waf_blocks = run_insights_query(
        WAF_LOG_GROUP,
        "fields @timestamp, action, httpRequest.clientIp as clientIp, httpRequest.uri as uri | filter action = \"BLOCK\" | stats count() as blocks by clientIp, uri | sort blocks desc | limit 25",
        start_ts, end_ts
    )

    # 3) Build an evidence bundle (JSON)
    incident_id = f"vandelay-{datetime.datetime.utcnow().strftime('%Y%m%d-%H%M%S')}"
    evidence = {
        "incident_id": incident_id,
        "time_window_utc": {"start": start_ts, "end": end_ts},
        "event": event,
        "ssm_params": params,
        "secret_meta": {k: secret.get(k) for k in ("host", "port", "dbname", "username") if k in secret},
        "queries": {
            "app_errors": app_errors,
            "app_rate": app_rate,
            "waf_actions": waf_actions,
            "waf_blocks": waf_blocks
        }
    }

    # 4) Prompt Bedrock to generate an incident report
    prompt = f"""
You are an SRE generating a concise, high-signal incident report in MARKDOWN.

Use ONLY the provided evidence. Do not invent facts.
If evidence is missing, write "Unknown" and recommend what to collect next.

Output MUST follow this exact template headings:
{INCIDENT_TEMPLATE()}

EVIDENCE (JSON):
{json.dumps(evidence, indent=2)}
"""

    print("Generating report with Bedrock...")
    bedrock_report = bedrock_generate(prompt)
    print(f"Report generated, length: {len(bedrock_report)} chars")

    # 5) Store artifacts
    md_key = f"reports/{incident_id}.md"
    json_key = f"reports/{incident_id}.json"

    s3.put_object(
        Bucket=REPORT_BUCKET,
        Key=json_key,
        Body=json.dumps(evidence, indent=2).encode("utf-8"),
        ContentType="application/json"
    )
    s3.put_object(
        Bucket=REPORT_BUCKET,
        Key=md_key,
        Body=bedrock_report.encode("utf-8"),
        ContentType="text/markdown"
    )
    print(f"Stored reports: s3://{REPORT_BUCKET}/{md_key}")

    # 6) Notify
    msg = f"""Incident report generated!

📋 Report: s3://{REPORT_BUCKET}/{md_key}
📊 Evidence: s3://{REPORT_BUCKET}/{json_key}

Time window: {datetime.datetime.utcfromtimestamp(start_ts).isoformat()}Z to {datetime.datetime.utcfromtimestamp(end_ts).isoformat()}Z

To download:
  aws s3 cp s3://{REPORT_BUCKET}/{md_key} ./{incident_id}.md
  aws s3 cp s3://{REPORT_BUCKET}/{json_key} ./{incident_id}.json
"""
    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=f"[IR Report] {incident_id}",
        Message=msg
    )
    print("SNS notification sent")

    return {
        "ok": True,
        "incident_id": incident_id,
        "report_s3": f"s3://{REPORT_BUCKET}/{md_key}",
        "evidence_s3": f"s3://{REPORT_BUCKET}/{json_key}"
    }


def INCIDENT_TEMPLATE():
    return """# Incident Report: {{incident_id}} — {{title}}

## 1. Executive Summary
- Impact:
- Customer/User Symptoms:
- Detection Method (alarm/logs):
- Severity:
- Start Time (UTC):
- End Time (UTC):
- Duration:

## 2. Timeline (UTC)
| Time | Signal | Evidence |
|------|--------|----------|
|      | Alarm triggered | |
|      | First error seen | |
|      | Triage started | |
|      | Root cause identified | |
|      | Fix applied | |
|      | Service restored | |
|      | Alarm cleared | |

## 3. Scope and Blast Radius
- Affected components:
- Entry point (ALB / WAF):
- Downstream dependency (RDS):
- Regions/AZs:

## 4. Evidence Collected
### 4.1 CloudWatch Alarm
- Alarm name:
- Metric:
- Threshold:
- State changes:

### 4.2 App Logs (CloudWatch Logs Insights)
- Error rate over time (1m bins):
- Top error signatures (top 5):
- Most recent error lines (top 10):

### 4.3 WAF Logs (CloudWatch Logs Insights)
- Allow vs Block:
- Top client IPs:
- Top URIs:
- Top terminating rules:

### 4.4 Configuration Sources (for Recovery)
- Parameter Store: /lab/db/* (endpoint/port/name)
- Secrets Manager: {{secret_name}} (host/port/dbname/username/password)
- Notes on drift:

## 5. Root Cause Analysis
- Root cause category: (Cred drift | Network isolation | DB interruption | External attack | Other)
- Exact failure mechanism:
- Why it wasn't prevented:
- Contributing factors:

## 6. Resolution
- Actions taken:
- Validation checks:
- Evidence of recovery (curl + alarm OK + logs stabilized):

## 7. Preventive Actions
- Immediate (today):
- Short-term (1–2 weeks):
- Long-term (1–2 months):

## 8. Appendix
- Key CLI commands used:
- Logs Insights queries used:
- Report generated by: Amazon Bedrock model {{model_id}}
"""
