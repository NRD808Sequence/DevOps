# Lab-2 Jenkins Pipeline Report
**Date:** 2026-04-13  
**Build:** #21 — SUCCESS  
**Job:** `vandelay-lab2-pipeline`  
**Jenkins:** https://jenkins.keepuneat.click  
**Repo:** NRD808Sequence/DevOps → G-Check/Jenkinsfile  
**Branch:** main  

---

## Build Result

| Field | Value |
|---|---|
| Build # | 21 |
| Result | SUCCESS |
| Stages | 12 / 12 |
| Gate Tests | GREEN |
| Rover SVG | Generated + Archived |
| EC2 Stability | Stable (no crash) |

---

## Pipeline Stages — Build #21

| # | Stage | Result | Notes |
|---|---|---|---|
| 1 | Checkout | PASS | G-Check/Jenkinsfile from main |
| 2 | TF Init | PASS | Backend: class7-armagaggeon-tf-bucket |
| 3 | TF Validate | PASS | No syntax errors |
| 4 | TF Plan | PASS | 0 changes (infra stable) |
| 5 | Approval Gate | PASS | Auto-approved (no DESTROY param) |
| 6 | TF Apply | PASS | 0 changes applied |
| 7 | Extract Outputs | PASS | ALB DNS, EC2 IPs resolved |
| 8 | Smoke Test | PASS | HTTP 200 from app endpoint |
| 9 | Gate Tests | GREEN | All assertions passed |
| 10 | Rover Image | PASS | `docker image inspect rover-tf-1.5.7:latest` (instant — pre-built) |
| 11 | Rover Graph | PASS | `rover.svg` generated + archived as build artifact |
| 12 | Notify | PASS | SNS notification dispatched |

---

## Evolution Across Sessions

### Session 1 — 2026-04-05 (Builds #17 / #18)

**State:** First working pipeline on Class7ZION repo  
**Jenkins:** `http://18.234.188.25:8080` (HTTP, no ALB, no TLS)  
**Stages:** 10  
**Repo:** Class7ZION/Class-7-Armageddon  

| Capability | Status |
|---|---|
| TF Init / Validate / Plan / Apply | Yes |
| Smoke Test | Yes |
| Gate Tests | Yes |
| Rover Graph | No |
| HTTPS / Domain | No (HTTP only) |
| Persistent Jenkins home (EBS) | No |
| Swap / OOM protection | No |
| EC2 lifecycle protection | No |
| Build status badge | No |
| Cleaned git history | No |

---

### Session 2 — 2026-04-11 (Build #12)

**State:** Migrated to NRD808Sequence/DevOps canonical repo; Jenkins behind ALB with ACM cert  
**Jenkins:** `https://jenkins.keepuneat.click` (HTTPS, ALB, Route 53)  
**Stages:** 13  

**Changes from Session 1:**
- Moved to NRD808Sequence/DevOps (G-Check subdirectory)
- HTTPS via ALB + ACM cert + Route 53 `jenkins.keepuneat.click`
- Blue Ocean UI installed
- Persistent 20 GB EBS volume for Jenkins home (`/dev/xvdf` → `/var/lib/jenkins`)
- Approval Gate stage added (parameterized DESTROY gate)
- Gate Tests expanded (HTTP 200 check + response body assertion)
- SNS Notify stage added

| Capability | Status |
|---|---|
| TF Init / Validate / Plan / Apply | Yes |
| Smoke Test | Yes |
| Gate Tests | Yes (expanded) |
| Rover Graph | No |
| HTTPS / Domain | Yes — `jenkins.keepuneat.click` |
| Persistent Jenkins home (EBS) | Yes — 20 GB gp3 |
| Swap / OOM protection | No |
| EC2 lifecycle protection | No |
| Build status badge | No |
| Cleaned git history | No |

---

### Session 3 — 2026-04-13 (Build #21)

**State:** All stability bugs resolved; Rover Graph integrated; full 12-stage run  
**Jenkins:** `https://jenkins.keepuneat.click` (unchanged)  
**Stages:** 12 (consolidated from 13; Rover Image + Rover Graph added)  

**Changes from Session 2:**

| Fix | Detail |
|---|---|
| EC2 self-termination bug | `lifecycle { ignore_changes = [user_data, ami] }` added to `aws_instance.vandelay_jenkins` in `26-jenkins.tf`. Terraform was stopping the EC2 on `user_data` hash change, killing mid-pipeline builds. |
| OOM crash (t3.medium) | 2 GB swap file added to `jenkins_user_data.sh` (step 0, before any package installs). AL2023 ships with 0 swap; Docker + Java + plugin install simultaneously exhausted 4 GB RAM. |
| Rover Docker image | `rover-tf-1.5.7:latest` pre-built once via SSM (531 MB). Stage 10 runs `docker image inspect` only — instant, zero memory impact. |
| Rover TF version mismatch | Rover container (TF 1.5.7) couldn't parse `.terraform/` backend state written by TF 1.14.8. Fixed by passing `--entrypoint sh` and prepending `terraform init -reconfigure` inside container before `rover -genImage`. |
| Git history cleanup | Removed Claude co-author lines from all 16 commits using `git-filter-repo`. Force-pushed all branches. |
| Build status badge | Embeddable Build Status badge added to `DevOps/README.md` and `G-Check/README.md`. Requires anonymous `Job/Read` permission (set in Jenkins). |

| Capability | Status |
|---|---|
| TF Init / Validate / Plan / Apply | Yes |
| Smoke Test | Yes |
| Gate Tests | GREEN |
| Rover Graph | Yes — `rover.svg` archived |
| HTTPS / Domain | Yes |
| Persistent Jenkins home (EBS) | Yes |
| Swap / OOM protection | Yes — 2 GB swap |
| EC2 lifecycle protection | Yes — `ignore_changes` |
| Build status badge | Yes — both READMEs |
| Cleaned git history | Yes — co-author removed |

---

## Gate Test Results — Build #21

```
[Pipeline] sh
+ curl -sf -o /dev/null -w '%{http_code}' http://vandelay-alb...
200
GATE: HTTP smoke test PASSED
GATE: Content check PASSED
All gates GREEN
```

---

## Rover Graph

`rover.svg` generated and archived as build artifact in Build #21.  
Visualizes the full Terraform resource graph for the Lab-2 G-Check stack.

Pre-build approach (SSM, off-pipeline):
```bash
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --parameters '{"commands":["docker build -t rover-tf-1.5.7:latest https://raw.githubusercontent.com/im2nguyen/rover/main/Dockerfile"]}' \
  --targets '[{"Key":"instanceIds","Values":["i-0b213638790499eac"]}]'
```

Runtime (Stage 11 Jenkinsfile):
```groovy
docker run --rm \
  -v "${WORKSPACE}/${TF_DIR}:/src" \
  -v "$HOME/.aws:/root/.aws:ro" \
  -e TF_VAR_db_password="$TF_VAR_db_password" \
  --entrypoint sh \
  rover-tf-1.5.7:latest \
  -c "terraform -chdir=/src init -reconfigure -backend=true && rover -workingDir /src -genImage"
```

---

## Infrastructure Reference

| Resource | Value |
|---|---|
| Jenkins EC2 | i-0b213638790499eac (t3.medium, us-east-1) |
| Jenkins URL | https://jenkins.keepuneat.click |
| App EC2 | i-07b8927bd2f48edef @ 100.53.95.30 |
| RDS | vandelay-rds01.cmrys4aosktq.us-east-1.rds.amazonaws.com |
| TF State Bucket | class7-armagaggeon-tf-bucket |
| Jenkins EBS | /dev/xvdf → /var/lib/jenkins (20 GB gp3) |
