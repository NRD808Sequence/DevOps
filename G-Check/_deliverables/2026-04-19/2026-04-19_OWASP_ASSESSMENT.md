# OWASP Security Assessment — Vandelay Lab-2 + jenkins-s3-test
**Date:** 2026-04-19
**Assessor:** Claude (OWASP Security Advisor)
**Scope:** Full infrastructure review — `vandelay-lab2-pipeline`, `jenkins-s3-test`, all Terraform, Jenkins bootstrap

---

## Overall Posture

IMDSv2 enforced on both EC2s, origin cloaking (CloudFront prefix list + HMAC header), dual-layer WAF (CloudFront + ALB), SG-to-SG rules, Secrets Manager with 30-day rotation, SSM instead of SSH, least-privilege EC2 IAM policies. Significantly above average for a lab environment.

The findings below are the gaps that still exist.

---

## CRITICAL

### C1 — A03 Injection: `TF_DIR` Parameter Is a Docker Volume Path Injection

**Files:** `G-Check/Jenkinsfile:149`, `G-Check/Jenkinsfile:479`

```groovy
// Stage: Pike Scan
--volume "${WORKSPACE}/${TF_DIR}:/tf"

// Stage: Rover Graph
-v "${env.WORKSPACE}/${params.TF_DIR}:/src"
```

`TF_DIR` is a free-text build parameter. Any user with **Build with Parameters** access can set it to `../../etc` or `../../root/.ssh` and mount arbitrary host filesystem paths into the Docker container. On the Jenkins host, the jenkins user runs Docker — this is full host compromise.

**Fix:** Validate `TF_DIR` before any stage uses it:

```groovy
stage('Validate Parameters') {
    steps {
        script {
            if (!(params.TF_DIR ==~ /^[a-zA-Z0-9_\-\/]+$/)) {
                error("TF_DIR contains invalid characters: ${params.TF_DIR}")
            }
            if (params.TF_DIR.contains('..')) {
                error("TF_DIR path traversal detected")
            }
        }
    }
}
```

---

### C2 — A04 Insecure Design: `DESTROY + AUTO_APPROVE` Bypasses Every Safety Gate

**File:** `G-Check/Jenkinsfile:56-63`

```groovy
booleanParam(name: 'AUTO_APPROVE', defaultValue: false, ...)
booleanParam(name: 'DESTROY',      defaultValue: false, ...)
```

Any user who can click **Build with Parameters** can set both to `true` and tear down the entire AWS infrastructure — VPC, RDS, EC2, ALB, CloudFront — with no approval gate, no confirmation. The Destroy Approval Gate is explicitly skipped when `AUTO_APPROVE=true`.

**Fix:** Restrict parameterized builds to `admin` only via project-based matrix auth. Additionally add a hard block in the pipeline:

```groovy
stage('Validate Parameters') {
    steps {
        script {
            if (params.DESTROY && params.AUTO_APPROVE) {
                def caller = currentBuild.rawBuild.getCause(
                    hudson.model.Cause.UserIdCause)?.userId
                if (caller != 'admin') {
                    error("DESTROY+AUTO_APPROVE requires admin. Triggered by: ${caller}")
                }
            }
        }
    }
}
```

---

### C3 — A02 Credential Management: `JenkinsTest01` Has `AdministratorAccess`

**Location:** IAM group `2026.04.17_JenkinsTest`

The `jenkins-s3-test` pipeline needs: `sts:GetCallerIdentity`, `s3:*` on one bucket, and Terraform state operations. It has `AdministratorAccess` — full account root-equivalent. If this key is ever exfiltrated (leaked in a log, stolen via SSRF, committed to Git), the entire AWS account is compromised.

**Fix:** Scope to exactly what's needed:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["sts:GetCallerIdentity"],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject","s3:GetObject","s3:DeleteObject","s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::class7-armagaggeon-tf-bucket",
        "arn:aws:s3:::class7-armagaggeon-tf-bucket/jenkins-artifacts/*",
        "arn:aws:s3:::class7-armagaggeon-tf-bucket/jenkins-s3-test/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": ["s3:CreateBucket","s3:DeleteBucket","s3:GetBucketTagging","s3:PutBucketTagging"],
      "Resource": "arn:aws:s3:::jenkins-bucket-*"
    }
  ]
}
```

---

## HIGH

### H1 — A08 Software Integrity: Docker Images Pulled Without Digest Pinning

**Files:** `G-Check/Jenkinsfile:150`, `jenkins-s3-test/Jenkinsfile:86`

```sh
docker run --rm ... jameswoolfenden/pike scan ...
```

`jameswoolfenden/pike` is pulled from Docker Hub with no digest. If the image tag is updated maliciously or the account is compromised, the next build silently runs attacker-controlled code inside CI with access to AWS credentials and the Jenkins workspace. Classic supply chain attack vector.

**Fix:** Pin to the specific digest you've tested:

```sh
# Get current digest
docker inspect --format='{{index .RepoDigests 0}}' jameswoolfenden/pike

# Use in Jenkinsfile
docker run --rm jameswoolfenden/pike@sha256:<digest> scan ...
```

---

### H2 — A08 Software Integrity: Plugin Manager JAR Downloaded Without Checksum

**File:** `jenkins_user_data.sh:135-137`

```bash
curl -sL -o "$PIM_JAR" \
  "https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/2.12.15/jenkins-plugin-manager-2.12.15.jar"
```

No checksum verification. If the download is intercepted (MITM, CDN compromise, DNS hijack), a malicious JAR installs arbitrary Jenkins plugins on bootstrap. The JAR runs at EC2 startup with root privileges.

**Fix:** Add SHA256 verification immediately after download:

```bash
EXPECTED_SHA256="<hash from GitHub release page>"
echo "${EXPECTED_SHA256}  ${PIM_JAR}" | sha256sum -c -
```

---

### H3 — A09 Security Logging: No CloudTrail Configured

**All `.tf` files** — no `aws_cloudtrail` resource anywhere.

CloudTrail is the audit log for all AWS API calls — IAM changes, EC2 start/stop, S3 access, secret reads. Without it you cannot answer "who deleted that resource?", "who accessed the RDS password?", or "was there unauthorized API activity?" after an incident. This is a compliance gap in any real environment.

**Fix — add `17-cloudtrail.tf`:**

```hcl
resource "aws_cloudtrail" "vandelay_trail" {
  name                          = "${local.name_prefix}-trail"
  s3_bucket_name                = aws_s3_bucket.vandelay_deliverables.id
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_log_file_validation    = true

  tags = local.common_tags
}
```

---

### H4 — A01 Access Control: Jenkins IAM Role Has `iam:*` on `Resource: "*"`

**File:** `26-jenkins.tf:92-100`

```hcl
Action   = ["ec2:*", "elasticloadbalancing:*", "rds:*", ..., "iam:*", ...]
Resource = "*"
```

`iam:*` on `*` means Jenkins can create new IAM users, attach `AdministratorAccess` to any role, and create access keys for any user — full privilege escalation to account ownership. Even with IMDSv2, a compromised build (malicious Jenkinsfile, poisoned plugin) results in account takeover.

**Mitigation:** Attach a Permission Boundary to cap what Jenkins's IAM actions can grant:

```hcl
resource "aws_iam_policy" "jenkins_boundary" {
  name = "JenkinsPermissionBoundary"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:*","rds:*","s3:*","secretsmanager:*","cloudfront:*",
          "wafv2:*","route53:*","logs:*","ssm:*","sns:*","acm:*",
          "lambda:*","elasticloadbalancing:*"
        ]
        Resource = "*"
      },
      {
        Effect   = "Deny"
        Action   = ["iam:CreateUser","iam:AttachUserPolicy","iam:CreateAccessKey"]
        Resource = "*"
      }
    ]
  })
}
```

---

### H5 — A05 Misconfiguration: TF State Bucket Has No Explicit Encryption or Versioning

**File:** `00-auth.tf:20-24`

The TF state file contains: RDS password, `X-Vandelay-Secret` origin cloaking value, all resource IDs and ARNs. No versioning means a state corruption or accidental overwrite is unrecoverable. No SSE-KMS means anyone with S3 read access gets all secrets in plaintext.

**Fix — add `tf-state-hardening.tf`:**

```hcl
resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = "class7-armagaggeon-tf-bucket"
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = "class7-armagaggeon-tf-bucket"
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}
```

---

## MEDIUM

### M1 — A05 Misconfiguration: RDS `skip_final_snapshot = true`

**File:** `07-compute.tf:18`

```hcl
skip_final_snapshot = true
```

If `terraform destroy` runs, the RDS instance is deleted with no snapshot. All application data is permanently gone with no recovery path.

**Fix:** Set `skip_final_snapshot = false` and add `final_snapshot_identifier = "${local.name_prefix}-final-snapshot"`.

---

### M2 — A05 Misconfiguration: ALB Deletion Protection Disabled

**File:** `11-bonus-b.tf:114`

```hcl
enable_deletion_protection = false
```

`terraform destroy` or an accidental apply removes the ALB with no confirmation prompt. In any production context this should be `true`.

---

### M3 — A06 Vulnerable Components: Rover Container Uses Terraform 1.5.7 (EOL)

Terraform 1.5.x reached end-of-life. The constraint is real — Rover requires 1.5.x for plan JSON format compatibility — but the image should be rebuilt with the latest 1.5.x patch release and pinned by digest to avoid silent version drift.

---

### M4 — A09 Logging: No Pipeline Failure Notifications

**File:** `G-Check/Jenkinsfile:528-531`

The `post { failure { } }` block only prints to the Jenkins console. If the pipeline fails overnight, nobody is alerted. No Slack, no email, no SNS.

**Fix:**

```groovy
failure {
    mail to: 'ops@example.com',
         subject: "FAILED: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
         body: "Build failed at ${env.BUILD_URL}"
}
```

---

### M5 — A01 Access Control: Incident Reporter Lambda Logs Policy Uses `Resource: "*"`

**File:** `15-incident-reporter.tf:154-163`

```hcl
Action   = ["logs:StartQuery", "logs:GetQueryResults", "logs:GetLogEvents", ...]
Resource = "*"
```

The Lambda can query ANY CloudWatch log group in the account — Jenkins logs, WAF logs, security logs. Scope it to the specific log groups it needs (`/aws/ec2/vandelay-rds-app`, `aws-waf-logs-vandelay-webacl`).

---

### M6 — A04 Insecure Design: `jenkins-s3-test` Has No Approval Gate Timeout

**File:** `jenkins-s3-test/Jenkinsfile:116`

The `input` approval gate has no `timeout`. If the gate is never clicked, the build holds a Jenkins executor indefinitely, blocking all other pipelines that need `agent any`.

**Fix:** Add a timeout to the input step:

```groovy
timeout(time: 30, unit: 'MINUTES') {
    input message: 'Review the plan above. Proceed?', ok: 'Deploy'
}
```

---

## LOW

### L1 — A02 Cryptographic Failures: Origin Secret Stored in Terraform State Plaintext

**File:** `21-cloudfront-origin-cloaking.tf:44-47`

`random_password.vandelay_origin_secret01` is stored in TF state in plaintext. If state is read, the CloudFront bypass header value is exposed. Mitigated by state bucket access controls, but ideally this secret should live in Secrets Manager with a data source reference.

---

### L2 — A07 Auth Failures: No Jenkins Audit Trail Plugin

The plugin list in `jenkins_user_data.sh` does not include `audit-trail`. There is no record of who approved builds, who ran Script Console commands, or who modified credentials. Add `audit-trail` to the `PLUGINS` array in `jenkins_user_data.sh`.

---

### L3 — A05 Misconfiguration: Bonus EC2 Instance Missing IMDSv2

**File:** `11-bonus-b.tf:24-38`

`vandelay_ec201_private_bonus` is missing the `metadata_options` block present on both the main app EC2 and Jenkins EC2. It uses the same IAM instance profile as the main app EC2, so IMDSv1 on this instance is still an SSRF risk.

**Fix:** Add to `aws_instance.vandelay_ec201_private_bonus`:

```hcl
metadata_options {
  http_tokens   = "required"
  http_endpoint = "enabled"
}
```

---

## Summary Table

| ID | OWASP | Severity | Finding | File |
|----|-------|----------|---------|------|
| C1 | A03 | 🔴 CRITICAL | TF_DIR param → Docker volume path injection | `Jenkinsfile:149,479` |
| C2 | A04 | 🔴 CRITICAL | DESTROY+AUTO_APPROVE bypasses all safety gates | `Jenkinsfile:56-63` |
| C3 | A02 | 🔴 CRITICAL | JenkinsTest01 AdministratorAccess | IAM |
| H1 | A08 | 🟠 HIGH | Pike/Rover images unpinned — supply chain risk | Both Jenkinsfiles |
| H2 | A08 | 🟠 HIGH | Plugin manager JAR no checksum | `jenkins_user_data.sh:135` |
| H3 | A09 | 🟠 HIGH | No CloudTrail | Missing |
| H4 | A01 | 🟠 HIGH | Jenkins role `iam:*` on `Resource: "*"` | `26-jenkins.tf:92` |
| H5 | A05 | 🟠 HIGH | TF state bucket no encryption or versioning | `00-auth.tf:20` |
| M1 | A05 | 🟡 MEDIUM | RDS `skip_final_snapshot = true` — data loss on destroy | `07-compute.tf:18` |
| M2 | A05 | 🟡 MEDIUM | ALB deletion protection disabled | `11-bonus-b.tf:114` |
| M3 | A06 | 🟡 MEDIUM | Rover uses EOL Terraform 1.5.7 | `Dockerfile.rover` |
| M4 | A09 | 🟡 MEDIUM | No pipeline failure notifications | `Jenkinsfile:528` |
| M5 | A01 | 🟡 MEDIUM | Lambda logs policy `Resource: "*"` | `15-incident-reporter.tf:154` |
| M6 | A04 | 🟡 MEDIUM | jenkins-s3-test input gate has no timeout | `jenkins-s3-test/Jenkinsfile:116` |
| L1 | A02 | 🟢 LOW | Origin secret stored in TF state plaintext | `21-cloudfront-origin-cloaking.tf:44` |
| L2 | A07 | 🟢 LOW | No audit-trail Jenkins plugin | `jenkins_user_data.sh` |
| L3 | A05 | 🟢 LOW | Bonus EC2 missing IMDSv2 | `11-bonus-b.tf:24` |

---

## Already Fixed This Session ✅

| Fix | OWASP | File |
|-----|-------|------|
| IMDSv2 enforced on Jenkins EC2 | A10 | `26-jenkins.tf` |
| IMDSv2 enforced on App EC2 | A10 | `07-compute.tf` |
| EC2 SG `0.0.0.0/0:80` removed — ALB SG only | A05 | `02-sg.tf` |
| GitHub webhook HMAC secret set | A07 | Jenkins UI |
| Jenkins authentication enabled (no more anonymous admin) | A07 | Jenkins UI |
| Jenkins setup wizard disabled at bootstrap | A05 | `jenkins_user_data.sh` |

---

## Recommended Fix Priority

1. **C1** — TF_DIR path validation (one Jenkinsfile stage, 10 minutes)
2. **C2** — DESTROY+AUTO_APPROVE admin-only guard (one Jenkinsfile stage, 10 minutes)
3. **C3** — Scope JenkinsTest01 IAM policy down (IAM console, 15 minutes)
4. **H3** — Add CloudTrail Terraform resource (new `.tf` file, 20 minutes)
5. **H5** — Add state bucket versioning + SSE-KMS (new `.tf` file, 15 minutes)
6. **L3** — Add IMDSv2 to bonus EC2 (one-line fix, 5 minutes)
