# 🚀 Vandelay Lab-2 — Pipeline Engineering Report
**Date:** 2026-04-19
**Engineer:** Niko Farias
**Pipeline:** `vandelay-lab2-pipeline` | Build #5 ✅ SUCCESS
**Jenkins:** https://jenkins.keepuneat.click
**Repo:** https://github.com/NRD808Sequence/DevOps

---

## 📋 Session Summary

Five engineering tasks completed today covering security hardening, runtime fixes, credential architecture, and pipeline observability.

---

## 🔒 1. Jenkins Security — Enabled Authentication

**Problem:** Jenkins was running with `SecurityRealm$None` — no login required, full anonymous access.

**Fix applied via Script Console:**
- Switched to `HudsonPrivateSecurityRealm` (local user database)
- Enabled `GlobalMatrixAuthorizationStrategy` with scoped permissions
- Created `admin` user with strong password
- Granted anonymous only `Jenkins.READ`, `Item.READ`, `Item.DISCOVER` (webhook minimum)

```mermaid
flowchart LR
    A[GitHub Webhook POST] -->|anonymous allowed| B[Jenkins.READ + Item.READ]
    B --> C[Pipeline Trigger ✅]
    D[Browser / Admin] -->|login required| E[admin credentials]
    E --> F[Full Jenkins UI ✅]
```

---

## 🛡️ 2. OWASP Top 10 Security Fixes

Three HIGH findings identified and remediated in infrastructure code.

### Findings Table

| # | OWASP | Severity | Finding | File | Status |
|---|-------|----------|---------|------|--------|
| 1 | A05 — Security Misconfiguration | 🔴 HIGH | EC2 SG allowed `0.0.0.0/0:80` — bypassed CloudFront WAF entirely | `02-sg.tf` | ✅ Fixed |
| 2 | A10 — SSRF | 🔴 HIGH | IMDSv1 enabled on Jenkins EC2 — `iam:*` role = full account takeover via SSRF | `26-jenkins.tf` | ✅ Fixed |
| 3 | A10 — SSRF | 🔴 HIGH | IMDSv1 enabled on App EC2 | `07-compute.tf` | ✅ Fixed |
| 4 | A07 — Auth Failure | 🔴 HIGH | GitHub webhook had no HMAC secret — any actor could trigger builds | Jenkins UI | ✅ Fixed |
| 5 | A02 — Credential Mgmt | 🟡 MEDIUM | Long-lived IAM user key (`JenkinsTest01`) with AdministratorAccess | IAM | ⚠️ Retained for lab |
| 6 | A05 — Misconfiguration | 🟢 LOW | Jenkins wizard not disabled at bootstrap | `jenkins_user_data.sh` | ✅ Fixed |

### Traffic Flow After A05 Fix

```mermaid
flowchart LR
    Internet -->|HTTPS| CF[CloudFront + WAF]
    CF -->|X-Vandelay-Secret header| ALB[Application Load Balancer]
    ALB -->|Port 80 — ALB SG only| EC2[App EC2]
    EC2 -.->|❌ Direct internet blocked| Internet
```

> **Before:** Two ingress rules — ALB SG AND `0.0.0.0/0`. Direct EC2 access bypassed all WAF rules.
> **After:** ALB SG only. All traffic must traverse CloudFront WAF → ALB.

---

## 🐍 3. Python Runtime Upgrade — 3.9 → 3.12

**Problem:** AL2023 default `python3` resolved to Python 3.9, which reached **end-of-life October 2025** — no security patches.

| | Before | After |
|---|---|---|
| `python3 --version` | `3.9.25` (EOL) | `3.12.12` ✅ |
| `python --version` | command not found | `3.12.12` ✅ |
| `java -version` | OpenJDK 21.0.10 | OpenJDK 21.0.10 (unchanged) |
| `terraform version` | 1.14.8 | 1.14.8 (unchanged) |
| `aws --version` | 2.33.15 / Python 3.9 | 2.33.15 (bundled Python, unchanged) |

**Root cause bug introduced and fixed:** `alternatives --set python3 python3.12` changed `/usr/bin/python3` to point to 3.12, but the `awscli2` rpm shebang (`#!/usr/bin/python3`) caused every `aws` CLI call to fail with `ModuleNotFoundError: No module named 'awscli'`.

**Fix:** Pinned `/usr/bin/aws` shebang to `#!/usr/bin/python3.9 -s` — `awscli` module only installed under 3.9.

```mermaid
flowchart TD
    A[dnf install python3.12] --> B[alternatives --set python3 python3.12]
    B --> C[/usr/bin/python3 → python3.12]
    C --> D{/usr/bin/aws shebang = #!/usr/bin/python3}
    D -->|python3.12 has no awscli| E[❌ ModuleNotFoundError]
    D -->|FIX: shebang → python3.9| F[✅ aws CLI works]
    C --> G[python3 --version = 3.12.12 ✅]
    C --> H[python --version = 3.12.12 ✅]
```

---

## 🔑 4. AWS Credential Architecture — Dual Posture

Two credential methods are now configured in Jenkins. This demonstrates both the instructor-required pattern and the hardened production pattern.

### Comparison

| | 🔑 JenkinsTest01 (IAM User) | 🏷️ vandelay-jenkins-role (Instance Profile) |
|---|---|---|
| **Type** | Static access key | Auto-rotating STS token |
| **Key ID** | `AKIATDDDPJRGCJXLPGTM` | None — no key exists |
| **Lifetime** | Permanent until deleted | ~1 hour, auto-renewed |
| **Scope** | `AdministratorAccess` (full account) | Scoped `VandelayTerraformDeployPolicy` |
| **Jenkins credential** | `JenkinsTest01` (AWS Credentials type) | Implicit — no credential needed |
| **Used by** | `jenkins-s3-test` pipeline | `vandelay-lab2-pipeline` |
| **OWASP A02** | ⚠️ Non-compliant | ✅ Compliant |
| **AWS best practice** | Teaching pattern | Production pattern |

### Credential Flow Diagram

```mermaid
flowchart TB
    subgraph Lab ["🏫 Lab Pattern (JenkinsTest01)"]
        J1[Jenkins pipeline] -->|withCredentials credentialsId JenkinsTest01| K1[Access Key injected as env vars]
        K1 -->|AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY| S1[AWS API]
        S1 --> I1[sts:get-caller-identity → user/JenkinsTest01]
    end

    subgraph Prod ["🏭 Production Pattern (Instance Profile)"]
        J2[Jenkins pipeline] -->|No credential block needed| K2[SDK auto-fetches from IMDS]
        K2 -->|IMDSv2 PUT token → temp creds| S2[AWS API]
        S2 --> I2[sts:get-caller-identity → assumed-role/vandelay-jenkins-role]
    end
```

> 💡 **Why instructors teach the IAM user pattern first:**
> - Makes credentials explicit and visible in the pipeline
> - Portable — works outside of AWS (GitHub Actions, local machines)
> - Forces understanding of the credential injection chain
> - Creates a concrete "before" state to contrast against instance profiles

---

## 🏗️ 5. Pipeline Build #5 — Full Success

### Stage Results

| Stage | Duration | Result |
|-------|----------|--------|
| Checkout | ~1s | ✅ |
| TF Init | ~8s | ✅ |
| TF Validate | ~7s | ✅ |
| Pike Scan | ~1s | ✅ |
| TF Plan | ~26s | ✅ No changes |
| Approval Gate | 18m 37s | ✅ Approved |
| TF Apply | ~13s | ✅ 0 added, 0 changed |
| Extract Outputs | ~17s | ✅ |
| Smoke Test | ~1s | ✅ HTTP 200 (CloudFront) |
| Gate Tests | ~17s | ✅ GREEN |
| Rover Image | ~1s | ✅ Cached |
| Rover Graph | ~49s | ✅ SVG generated |
| Notify | ~1s | ✅ |

### Gate Test Results — Build #5

```
Gate 1 — Secrets + EC2 Role    PASS ✅
  ├── aws sts get-caller-identity          PASS
  ├── secret lab/rds/mysql describable     PASS
  ├── no wildcard resource policy          PASS
  ├── instance profile attached            PASS
  └── resolved role: vandelay-ec2-role01   PASS

Gate 2 — Network + RDS          PASS ✅
  ├── aws sts get-caller-identity          PASS
  ├── RDS instance exists                  PASS
  ├── RDS not publicly accessible          PASS
  ├── DB port 3306 discovered              PASS
  ├── EC2 SG resolved                      PASS
  ├── RDS SG resolved                      PASS
  └── SG-to-SG port 3306 ingress present  PASS

BADGE: 🟢 GREEN
```

---

## 📡 6. Build Status Badges — README

**Plugin installed:** `embeddable-build-status v637.vd878e68178f8`

**Anonymous access configured** via Script Console (`VIEW_STATUS` + `Jenkins.READ` + `Item.READ`).

Both badges in `README.md` now resolve publicly:

| Pipeline | Badge URL | Status |
|----------|-----------|--------|
| `vandelay-lab2-pipeline` | `/buildStatus/icon?job=vandelay-lab2-pipeline` | ✅ HTTP 200 |
| `jenkins-s3-test` | `/buildStatus/icon?job=jenkins-s3-test` | ✅ HTTP 200 |

---

## 🪣 7. jenkins-s3-test Pipeline — Build #5 SUCCESS

IAM user credential architecture validated end-to-end. All 7 stages passed.

### Stage Results

| Stage | Result | Notes |
|-------|--------|-------|
| Checkout | ✅ | Commit `926c9be` |
| Set AWS Credentials | ✅ | `sts:get-caller-identity` → `user/JenkinsTest01` |
| S3 Artifact Test | ✅ | Upload → Download → Diff → Delete — PASSED |
| TF Init | ✅ | S3 backend configured (`class7-armagaggeon-tf-bucket`) |
| Pike Scan | ✅ | Minimum IAM policy generated (S3 + DynamoDB) |
| TF Plan | ✅ | 1 to add — `aws_s3_bucket.frontend` (`jenkins-bucket-*`) |
| TF Apply | ✅ | Bucket `jenkins-bucket-20260420040017755700000001` created |
| TF Destroy | ✅ | Bucket destroyed — clean teardown |

### S3 Round-Trip Proof

```
upload: ./test-artifact.txt → s3://class7-armagaggeon-tf-bucket/jenkins-artifacts/test-artifact-5.txt
download: s3://...test-artifact-5.txt → ./downloaded-artifact.txt
diff test-artifact.txt downloaded-artifact.txt
S3 ARTIFACT TEST PASSED
delete: s3://...test-artifact-5.txt
```

### Bugs Fixed to Get Here

| Build | Error | Root Cause | Fix |
|-------|-------|-----------|-----|
| #1 | `IncompleteSignature` | Wrong `AWSCredentialsImpl` parameter order — description used as key | Corrected order: `(scope, id, accessKey, secretKey, description)` |
| #2–3 | `SignatureDoesNotMatch` | Old/corrupted secret key | Deleted old IAM key, created new key pair |
| #4 | `No configuration files` | `terraform` running from repo root, not `jenkins-s3-test/` | Added `dir('jenkins-s3-test')` wrapper + fixed Pike volume mount |
| #5 | — | — | ✅ Full success |

---

## 📦 Commits This Session

| Hash | Message |
|------|---------|
| `ef80540` | OWASP security fixes — IMDSv2 on both EC2s + EC2 SG WAF bypass |
| `bc8719e` | Rover Graph TF_DIR interpolation fix |
| `db0497e` | Upgrade Jenkins bootstrap Python from EOL 3.9 to 3.12 |
| `6eb2771` | Add `/usr/bin/python` symlink to python3.12 at bootstrap |
| `f0e2c0a` | Fix aws CLI shebang after python3 alternatives change to 3.12 |
| `926c9be` | fix jenkins-s3-test: add dir(jenkins-s3-test) to TF stages and fix Pike volume mount |

---

## 🏛️ Infrastructure State (End of Session)

| Resource | ID / Value |
|----------|-----------|
| Jenkins EC2 | `i-0ea63c7bf813933c8` |
| App EC2 | `i-05ed1e67ab4e88ed8` |
| Jenkins URL | https://jenkins.keepuneat.click |
| App URL | https://app.keepuneat.click |
| RDS | `vandelay-rds01.cmrys4aosktq.us-east-1.rds.amazonaws.com` |
| CloudFront | `E1S240PLQQ8HKJ` |
| TF State Bucket | `class7-armagaggeon-tf-bucket` |
| Python (Jenkins host) | `3.12.12` |
| Terraform | `1.14.8` |
| Java | `OpenJDK 21.0.10` |

---

## ⚠️ Open Items

- [ ] **JenkinsTest01 access key** — new key active; deactivate after lab submission
- [ ] **JenkinsTest01 scope** — `AdministratorAccess` is intentionally broad for lab; scope down post-submission
- [ ] **Blue Ocean dashboard** — `blueocean-dashboard` meta-plugin install pending
- [x] **jenkins-s3-test pipeline** — created, credentialed, and run successfully ✅
