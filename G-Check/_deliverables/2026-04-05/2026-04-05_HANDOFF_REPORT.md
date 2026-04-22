# Lab-2 Vandelay Infrastructure — Handoff Report
**Date:** 2026-04-05
**Status:** LIVE — Pipeline GREEN
**Next Session:** Snyk DevSecOps Integration into Jenkins Pipeline

---

## 1. What's Running Right Now

### EC2 Instances (4 running — 2 are ORPHANS, see cost note)

| Instance ID | Name | Type | IP | Status | Notes |
|---|---|---|---|---|---|
| `i-0ae539b167d765370` | vandelay-jenkins | t3.medium | 18.234.188.25:8080 | **ACTIVE** | Pipeline host — Build #17/#18 ran here |
| `i-07be502d81275854c` | vandelay-ec201 | t3.micro | 35.175.217.81 | **ACTIVE** | Flask app — HTTP 200 confirmed |
| `i-035f0315cbd8e5141` | vandelay-ec201-private | t3.micro | (none) | **ACTIVE** | Private subnet EC2 — per Terraform |
| `i-0878a0ddfe28e5624` | vandelay-jenkins | t3.medium | 44.210.136.8:8080 | **⚠ ORPHAN** | Second Jenkins from prior run — not in TF state |

**Action:** Stop `i-0878a0ddfe28e5624` — it's burning ~$30/month and not managed by Terraform.

### RDS
| ID | Class | Engine | Status | Storage |
|---|---|---|---|---|
| `vandelay-rds01` | db.t3.micro | MySQL 8.4.7 | available | 20GB |

`PubliclyAccessible = False` ✓ — only reachable from EC2 SG-to-SG rule.

### Networking
| Resource | ID | Notes |
|---|---|---|
| NAT Gateway | `nat-02e488d821a685749` | us-east-1a — **$32/month** |
| ALB | `vandelay-alb01` | active, internet-facing |
| EIPs | 3 allocated, all associated | Free while associated |
| CloudFront | `E2J9Y6PVQFFAD2` | Deployed — `app.keepuneat.click` |
| VPC (active) | `vpc-0e050f5fa044e88db` | vandelay-vpc01 10.75.0.0/16 |
| VPC (orphan) | `vpc-07f63d2e128b8b78c` | ⚠ Second VPC same CIDR — from old targeted destroy |

### VPC Interface Endpoints — **⚠ HIDDEN COST**
There are **14 Interface endpoints** across 2 VPCs (7 per VPC: SSM, SSMMessages, EC2Messages, Secrets Manager, CloudWatch, KMS, Logs).
The orphan VPC has its own set of 7 endpoints still running.
**Gateway endpoints (S3) are free. Interface endpoints are NOT.**

### Security
| Resource | Status |
|---|---|
| WAF Regional (`vandelay-waf01`) | Active — 4 rules, attached to ALB |
| WAF CloudFront (`vandelay-cf-waf01`) | Active — on CloudFront distribution |
| SSH port 22 | **Removed today** — both SGs cleaned |
| SSM Session Manager | Online on both instances |
| Secrets Manager `lab/rds/mysql` | RotationEnabled=True, Lambda attached |

### S3 Buckets
| Bucket | Purpose |
|---|---|
| `class7-armagaggeon-tf-bucket` | Terraform remote state backend |
| `vandelay-alb-logs-[ACCOUNT_ID]` | ALB access logs |
| `vandelay-incident-reports-[ACCOUNT_ID]` | Lambda incident reporter output |
| `generals-fried-chicken-bucket-112525` | Public deliverables/screenshots |

---

## 2. Estimated Monthly Cost

> Prices are AWS us-east-1 on-demand rates. Assumes 730 hrs/month.

### Active (Terraform-managed) Resources

| Resource | Qty | Rate | Monthly |
|---|---|---|---|
| EC2 t3.medium (Jenkins) | 1 | $0.0416/hr | **$30.37** |
| EC2 t3.micro (app x2) | 2 | $0.0104/hr | **$15.18** |
| EBS gp3 20GB x2 | 2 | $0.08/GB | **$3.20** |
| EBS gp3 8GB x2 | 2 | $0.08/GB | **$1.28** |
| RDS db.t3.micro | 1 | $0.017/hr | **$12.41** |
| RDS storage 20GB | 1 | $0.115/GB | **$2.30** |
| NAT Gateway | 1 | $0.045/hr | **$32.85** |
| ALB | 1 | $0.008/hr + LCU | **~$6.00** |
| VPC Interface Endpoints | 7 | $0.01/hr each | **$51.10** |
| CloudFront | 1 | low traffic | **~$1.00** |
| WAF WebACLs x2 | 2 | $5.00/ACL | **$10.00** |
| Secrets Manager | 1 | $0.40/secret | **$0.40** |
| S3 (all buckets) | 4 | minimal | **~$2.00** |
| **Active Total** | | | **~$168/month** |

### Orphaned Resources (Wasted Spend)

| Resource | Monthly Cost |
|---|---|
| EC2 t3.medium (2nd Jenkins `i-0878a0ddfe28e5624`) | **$30.37** |
| VPC Interface Endpoints (orphan VPC x7) | **$51.10** |
| EBS volumes attached to orphan instances | **~$2.00** |
| **Waste Total** | **~$83/month** |

### Summary

| | Monthly |
|---|---|
| Current total (with orphans) | **~$251/month** |
| After cleanup (stop orphan Jenkins + delete orphan VPC endpoints) | **~$168/month** |
| If you stop ALL instances between sessions | **~$90/month** |

> **To save ~$83/month immediately:** Stop `i-0878a0ddfe28e5624` and delete the 7 Interface endpoints in VPC `vpc-07f63d2e128b8b78c`.

---

## 3. Access Quick Reference

| Resource | URL / Command |
|---|---|
| App (CloudFront) | https://app.keepuneat.click/ |
| App (direct EC2) | http://35.175.217.81/ |
| Jenkins UI | http://18.234.188.25:8080 |
| Jenkins login | ShogunnMaster / (stored in Secrets Manager) |
| EC2 SSH-free access | `aws ssm start-session --target i-07be502d81275854c` |
| Jenkins SSM | `aws ssm start-session --target i-0ae539b167d765370` |
| TF state bucket | `s3://class7-armagaggeon-tf-bucket/class7/fineqts/armageddontf/state-key` |
| Deliverables gallery | https://generals-fried-chicken-bucket-112525.s3.us-east-1.amazonaws.com/class7deliverables/g-checks/index.html |
| GitHub repo | https://github.com/NRD808Sequence/Class7ZION |

---

## 4. Security Scan Reminders — TODO Before Next Lab

> ⚠ Run these against your live infrastructure and pipeline before the Snyk workshop.

### Snyk (next workshop focus)
```bash
# Install
npm install -g snyk
snyk auth

# SCA — dependency vulnerabilities
cd Armageddon/lab-2 && snyk test

# SAST — source code vulnerabilities
snyk code test

# IaC — Terraform misconfigurations
snyk iac test Armageddon/lab-2/

# Report to Snyk UI
snyk iac test Armageddon/lab-2/ --report
```

### OWASP ZAP — Web app scan
```bash
# Against CloudFront endpoint
docker run -t owasp/zap2docker-stable zap-baseline.py \
  -t https://app.keepuneat.click/ \
  -r zap-report-$(date +%Y%m%d).html

# Full active scan (more thorough)
docker run -t owasp/zap2docker-stable zap-full-scan.py \
  -t https://app.keepuneat.click/
```

### Nmap — Port/service scan
```bash
# External scan of app EC2
nmap -sV -sC -p- 35.175.217.81

# Jenkins
nmap -sV -p 8080,22,443,80 18.234.188.25

# Verify port 22 is gone (should show filtered)
nmap -p 22 35.175.217.81 18.234.188.25
```

### Nikto — Web server vulnerabilities
```bash
nikto -h https://app.keepuneat.click
nikto -h http://35.175.217.81
```

### Trivy — Container/IaC scan
```bash
# IaC scan
trivy config Armageddon/lab-2/

# Secret scan
trivy fs --scanners secret Armageddon/lab-2/
```

### AWS Native Scans
```bash
# Inspector — EC2 vulnerability assessment
aws inspector2 enable --resource-types EC2

# SecurityHub findings
aws securityhub get-findings --filters '{"SeverityLabel":[{"Value":"CRITICAL","Comparison":"EQUALS"}]}'

# Config rules compliance
aws configservice describe-compliance-by-config-rule
```

---

## 5. Next Session — Snyk DevSecOps Workshop

**Repo:** NRD808Sequence/Class7ZION
**Reference video:** https://youtu.be/P803aLJ0VuM?si=Yn3EuE-IDyMJu4dO

### Pre-work checklist
- [ ] Create Snyk account at snyk.io (free tier works)
- [ ] Get Snyk API token (Settings → API Token)
- [ ] Get Snyk Org slug (visible in Snyk UI URL)
- [ ] Jenkins: Install **Snyk Security** plugin
- [ ] Jenkins credentials to add:
  - `snyk-api-token` — Type: **Snyk API Token**
  - `snyk-api-token-string` — Type: **Secret Text** (same token value — needed for CLI stage)
  - `snyk-org-slug` — Type: **Secret Text**
  - `github-creds` — Type: **Username/Password** (PAT with `repo` + `workflow` scopes)
- [ ] Jenkins → Tools → Snyk Installations: add `snyk` (Linux AMD64, explicit — not auto-detect)

### Jenkinsfile pipeline structure (two stages required)
```groovy
stage('Snyk CLI Scan') {
    // Prints findings to Jenkins console
    // Uses snyk-api-token-string credential
}
stage('Snyk Plugin Scan') {
    // Sends findings to Snyk UI via --report flag
    // Uses snyk-api-token (plugin type) + snyk-org-slug
    // Required for IaC + SAST ignores/documentation
}
```

### Known gotcha — `command not found` on first run
The Snyk CLI isn't on the Jenkins agent until the plugin stage runs it once.
**Fix sequence:**
1. Remove the CLI stage from Jenkinsfile
2. Run pipeline — plugin installs CLI on agent
3. Restore CLI stage
4. Re-run — both stages work

### Architecture note
Your Jenkins runs on EC2 AMD64 — no M-series ARM64 issue. The explicit `snyk` (Linux AMD64) tool install in Jenkins Tools config is still recommended to avoid auto-detect inconsistencies.

---

## 6. Completed This Session

| Item | Status |
|---|---|
| Migrated pipeline from shared repo → NRD808Sequence/Class7ZION | ✅ |
| Resolved 20+ orphaned resource import conflicts | ✅ |
| Fixed `aws_secretsmanager_secret_rotation` blocker via terraform import | ✅ |
| Build #17 — first full SUCCESS (16:10 runtime) | ✅ |
| Build #18 — clean zero-change idempotent run | ✅ |
| Gate tests GREEN both builds | ✅ |
| Removed SSH port 22 from both SGs (EC2 + Jenkins) | ✅ |
| Repo cleanup: .DS_Store, .claude/, binaries, Co-Authored-By removed | ✅ |
| Public S3 gallery with all screenshots | ✅ |
| Security scan of codebase — findings documented | ✅ |
