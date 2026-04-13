# Class 7 Gut Check — Submission

**Student:** Niko Farias
**GitHub Repo:** https://github.com/NRD808Sequence/DevOps
**Armageddon Class Repo:** https://github.com/Class-6-Hungry-Wolves/Class-7-Armageddon (branch: `nikrdf-armageddon-branch`)
**Submission Date:** 2026-04-13
**Jenkins:** https://jenkins.keepuneat.click

---

## Requirement Checklist

| Requirement | Evidence | File |
|---|---|---|
| Successful Jenkins pipeline run | vandelay-lab2-pipeline Build #23 — 12 stages, SUCCESS | `2026-04-13-g-check/2026-04-13_PIPELINE_REPORT.md` |
| Webhook auto-trigger (Git push → Jenkins) | Build #23 triggered by GitHub push by NRD808Sequence | `2026-04-11-gut-check-pipeline/screenshots/2026-04-11-gut-check-pipeline-github_webhook.png` |
| Terraform deployment of an S3 bucket | jenkins-s3-test Build #2 — bucket created + destroyed via pipeline | `../jenkins-s3-test/_deliverables/screenshots/` |
| Armageddon clearance from Theo | Email from Theo WAF — "Good job, you can continue with the class." | `screenshots/gmail-from-theodulfo.png` |
| S3 bucket contents screenshot | `class7-armagaggeon-tf-bucket` — TF state for both pipelines | *(see S3 section below)* |
| Terraform job output | TF Plan, gate JSONs, rover.svg archived as build artifacts | `2026-04-13-g-check/G-Check/tfplan.txt` |
| Armageddon repo link | Above | — |
| Personal GitHub account, no forks | NRD808Sequence/DevOps — personal account | — |
| All deployed via pipeline, not manually | All builds triggered by push or approved through pipeline gate | — |

---

## Pipeline 1 — vandelay-lab2-pipeline

**Job:** `vandelay-lab2-pipeline`
**Jenkins:** https://jenkins.keepuneat.click/job/vandelay-lab2-pipeline/
**Repo:** https://github.com/NRD808Sequence/DevOps (branch: `main`, path: `G-Check/`)
**Trigger:** GitHub push webhook → Jenkins → Terraform

| Build | Date | Trigger | Result | Notes |
|---|---|---|---|---|
| #21 | 2026-04-13 | GitHub push | SUCCESS | Full deploy, 12 stages, gates GREEN |
| #23 | 2026-04-13 | GitHub push by NRD808Sequence | SUCCESS | Zero-change idempotent run, gates GREEN |

**TF backend:** S3 (`class7-armagaggeon-tf-bucket/G-Check/`)
**Stages:** Checkout → TF Init → TF Validate → TF Plan → Approval Gate → TF Apply → Extract Outputs → Smoke Test → Gate Tests → Rover Image → Rover Graph → Notify

---

## Pipeline 2 — jenkins-s3-test

**Job:** `jenkins-s3-test`
**Jenkins:** https://jenkins.keepuneat.click/job/jenkins-s3-test/
**Repo:** https://github.com/NRD808Sequence/jenkins-s3-test (branch: `main`)
**Trigger:** Manual (Build #2)

| Build | Date | Result | Notes |
|---|---|---|---|
| #2 | 2026-04-13 | SUCCESS | S3 artifact test PASSED; `jenkins-bucket-20260413082939390800000001` created and destroyed via Terraform |

**TF backend:** S3 (`class7-armagaggeon-tf-bucket/jenkins-s3-test/`)
**Stages:** Set AWS Credentials → S3 Artifact Test → TF Init → TF Plan → TF Apply → TF Destroy

---

## Infrastructure Deployed via Pipeline

EC2 (Flask app) · RDS MySQL (private subnet) · ALB · CloudFront (`app.keepuneat.click`) ·
WAF (regional + CloudFront scope) · Secrets Manager + rotation Lambda · Jenkins CI/CD server
(behind ALB at `jenkins.keepuneat.click`) · VPC with public/private subnets + NAT ·
VPC endpoints (SSM, Secrets Manager, KMS, CloudWatch Logs) · EBS persistent Jenkins home volume

---

## Gate Test Results (Build #23)

```
Gate 1 — secrets_and_role : PASS
Gate 2 — network_db       : PASS
BADGE: GREEN
```
