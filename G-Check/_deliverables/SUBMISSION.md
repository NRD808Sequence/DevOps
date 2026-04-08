# Class 7 Gut Check — Submission

**Student:** Niko Farias
**GitHub Repo:** https://github.com/NRD808Sequence/DevOps
**Submission Date:** 2026-04-06

---

## Deliverables

| Requirement | File |
|---|---|
| Jenkins pipeline success (Build #17 + #18) | `screenshots/vandelay-lab2-mypipeline-17.png` |
| Pipeline stage view | `screenshots/vandelay-lab2-mypipeline-stages.png` |
| Pipeline step detail | `screenshots/vandelay-lab2-mypipeline-pipelinesteps.png` |
| Webhook auto-trigger | `screenshots/vandelay-lab2-mypipeline-GitHub hook.png` |
| GitHub webhook deliveries | `screenshots/vandelay-lab2-mypipeline-github-webhook.png` |
| Terraform deploy artifacts (S3 + gate JSONs) | `screenshots/vandelay-lab2-mypipeline-artifacts.png` |
| AWS infrastructure running | `screenshots/vandelay-lab2-mypipeline-AWS-stage-18.png` |
| Armageddon clearance from Theo | `screenshots/gmail-from-theodulfo.png` |

---

## Pipeline Summary

- **Job:** `vandelay-lab2-pipeline`
- **Trigger:** GitHub push webhook → Jenkins → Terraform
- **Build #17:** SUCCESS — full deploy, gates GREEN, 16:10 runtime
- **Build #18:** SUCCESS — zero-change idempotent run, gates GREEN, 1:49 runtime
- **TF backend:** S3 (`class7-armagaggeon-tf-bucket`)
- **Deployed via pipeline** (not manually)

## Infrastructure Deployed via Pipeline

EC2 (Flask app) · RDS MySQL (private) · ALB · CloudFront (`app.keepuneat.click`) ·
WAF (regional + CF scope) · Secrets Manager + rotation Lambda · Jenkins CI/CD server ·
VPC with public/private subnets + NAT · VPC endpoints (SSM, Secrets Manager, KMS, logs)
