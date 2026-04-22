# Lab-2 G-Check — Team Handoff Report
**Date:** 2026-04-13  
**Prepared by:** NRD808Sequence  
**Build:** #29 — all 13 stages SUCCESS  
**Status:** STABLE — pipeline is green, EC2 self-termination bug resolved  

---

## What Changed This Session

Three root-cause bugs were diagnosed and resolved. The pipeline is now stable and reproducible.

---

### Fix 1 — EC2 Self-Termination (Critical)

**Symptom:** Jenkins EC2 stopped mid-pipeline 3 times with stop reason `Client.UserInitiatedShutdown`.  
**Root cause:** `jenkins_user_data.sh` was modified (swap addition). Terraform detected the `user_data` hash change during Stage 6 (TF Apply) and issued an in-place stop/start to update the metadata — killing the running Jenkins process.  
**Fix:** Added `lifecycle { ignore_changes = [user_data, ami] }` to `aws_instance.vandelay_jenkins` in `26-jenkins.tf`.

```hcl
# 26-jenkins.tf
resource "aws_instance" "vandelay_jenkins" {
  ...
  lifecycle {
    ignore_changes = [user_data, ami]
  }
}
```

**Impact:** Terraform Apply no longer restarts the Jenkins host when user_data or AMI changes. Changes to `jenkins_user_data.sh` must be applied manually via SSM or via a deliberate destroy+recreate.

---

### Fix 2 — OOM Crash on t3.medium

**Symptom:** Jenkins instance unresponsive after heavy bootstrap (Docker install + Java + plugin download all concurrent).  
**Root cause:** AL2023 ships with 0 swap. t3.medium has 4 GB RAM. Docker daemon + Java heap + plugin installer exceeded available memory.  
**Fix:** Added a 2 GB swap file as step 0 in `jenkins_user_data.sh`, before any package installs.

```bash
# jenkins_user_data.sh — step 0
if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
```

**Note:** This change is in `user_data` and will NOT be applied to the running instance (see Fix 1 — `ignore_changes`). The swap was applied manually via SSM on the current instance. It will apply automatically on fresh bootstrap.

---

### Fix 3 — Rover Graph TF Version Mismatch

**Symptom:** Stage 11 (Rover Graph) failed with `unsupported attribute: allowed_account_ids`.  
**Root cause:** The pipeline uses Terraform 1.14.8 (installed on Jenkins host). The Rover container uses Terraform 1.5.7. The `.terraform/` backend state initialized by 1.14.8 contains attributes that 1.5.7's state format cannot parse.  
**Fix:** Pass `--entrypoint sh` to the docker run command and run `terraform init -reconfigure` inside the container (using 1.5.7) before invoking `rover -genImage`. This writes a fresh `.terraform/` state compatible with 1.5.7.

```groovy
// Jenkinsfile — Stage 11
sh '''
  docker run --rm \
    -v "${WORKSPACE}/${TF_DIR}:/src" \
    -v "$HOME/.aws:/root/.aws:ro" \
    -e TF_VAR_db_password="$TF_VAR_db_password" \
    --entrypoint sh \
    rover-tf-1.5.7:latest \
    -c "terraform -chdir=/src init -reconfigure -backend=true && rover -workingDir /src -genImage"
'''
```

---

## Infrastructure State — 2026-04-13

### Jenkins

| Resource | Value |
|---|---|
| Instance ID | i-0b213638790499eac |
| Instance Type | t3.medium |
| Region | us-east-1 |
| URL | https://jenkins.keepuneat.click |
| Swap | 2 GB (applied via SSM) |
| Jenkins Home | /var/lib/jenkins (EBS /dev/xvdf) |
| EBS Volume | 20 GB gp3 — `prevent_destroy = true` |
| IAM Role | vandelay-jenkins-role (SSM + CW + TF deploy) |
| Security Group | vandelay-jenkins-sg — no SSH, port 8080 from ALB only |
| Access | AWS SSM Session Manager only |

### Application

| Resource | Value |
|---|---|
| App EC2 | i-07b8927bd2f48edef |
| App IP | 100.53.95.30 |
| RDS Endpoint | vandelay-rds01.cmrys4aosktq.us-east-1.rds.amazonaws.com |
| ALB | vandelay-alb (HTTPS, ACM cert) |
| Domain | keepuneat.click (Route 53) |
| TF State Bucket | class7-armagaggeon-tf-bucket |

### Security Posture

| Control | Status |
|---|---|
| Jenkins SSH access | Removed — SSM only |
| App EC2 SSH access | Removed — SSM only |
| Jenkins on public internet | No — behind ALB (port 8080 blocked) |
| TLS | Yes — ACM cert on ALB |
| DB credentials in pipeline | Injected via Jenkins credentials store (not in code) |
| DB credentials in git | No — never committed |
| .tfvars gitignored | Yes |
| Git history | Clean — co-author lines removed from all 16 commits |

---

## Rover Docker Image

`rover-tf-1.5.7:latest` is pre-built on the Jenkins host (531 MB).  
Stage 10 runs `docker image inspect` only — it does NOT rebuild on each run.  
If the Jenkins instance is replaced, the image must be rebuilt:

```bash
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --parameters '{"commands":["docker build -t rover-tf-1.5.7:latest https://raw.githubusercontent.com/im2nguyen/rover/main/Dockerfile"]}' \
  --targets '[{"Key":"instanceIds","Values":["<new-instance-id>"]}]' \
  --region us-east-1
```

---

## Build Status Badge

Live build status is visible in both READMEs:

```markdown
[![vandelay-lab2-pipeline](https://jenkins.keepuneat.click/buildStatus/icon?job=vandelay-lab2-pipeline)](https://jenkins.keepuneat.click/job/vandelay-lab2-pipeline/)
```

Requires anonymous `Job/Read` permission set in Jenkins → Configure Global Security.

---

## Pike Scan — Build #29

**Tool:** `jameswoolfenden/pike` (Docker Hub)
**Stage:** 4 — runs after TF Validate, before TF Plan
**Artifact:** `pike-policy.json` — archived on every build
**Purpose:** Enumerates the minimum IAM permissions required to deploy this Terraform stack

```
26 statement blocks · 16 AWS services
ec2 · iam · rds · s3 · cloudfront · wafv2 · route53
alb · lambda · secretsmanager · sns · ssm · cloudwatch
logs · acm · serverlessrepo
```

Full output: `G-Check/_deliverables/2026-04-13-g-check/G-Check/pike-policy.json`

---

## Evolution Summary

| Date | Build | Stages | Rover | Pike | HTTPS | EBS | Swap | lifecycle fix |
|---|---|---|---|---|---|---|---|---|
| 2026-04-05 | #17/#18 | 10 | No | No | No | No | No | No |
| 2026-04-11 | #12 | 13 | No | No | Yes | Yes | No | No |
| 2026-04-13 | #29 | 13 | Yes | Yes | Yes | Yes | Yes | Yes |

---

## Pending Items

| Item | Priority | Notes |
|---|---|---|
| "Selected Git installation does not exist" warning | Low | Cosmetic — fix in Manage Jenkins → Tools → Git |
| SNS email confirmation | Low | Confirm subscription at gaijinmzungu@gmail.com for SNS notify stage |

---

## Operational Notes

**To apply `user_data` changes to running Jenkins:**  
Connect via SSM and run the relevant commands manually. Do NOT change `user_data` and push — TF Apply will detect the change but `ignore_changes` will suppress the restart. The running instance will not pick up the new script until a deliberate destroy+recreate.

**To destroy and recreate Jenkins:**  
1. Remove `lifecycle { prevent_destroy = true }` from `aws_ebs_volume.vandelay_jenkins_data` if you need to destroy the EBS
2. Remove `lifecycle { ignore_changes = [user_data, ami] }` from `aws_instance.vandelay_jenkins`
3. Run `terraform destroy -target=aws_instance.vandelay_jenkins`
4. Run `terraform apply`
5. Rebuild Rover Docker image via SSM (see above)

**To connect to Jenkins EC2:**
```bash
aws ssm start-session --target i-0b213638790499eac --region us-east-1
```

---

## Evolution Summary

| Date | Build | Stages | Repo | Jenkins URL | Rover | HTTPS | EBS | Swap | lifecycle fix |
|---|---|---|---|---|---|---|---|---|---|
| 2026-04-05 | #17/#18 | 10 | Class7ZION | 18.234.188.25:8080 | No | No | No | No | No |
| 2026-04-11 | #12 | 13 | NRD808Sequence/DevOps | jenkins.keepuneat.click | No | Yes | Yes | No | No |
| 2026-04-13 | #21 | 12 | NRD808Sequence/DevOps | jenkins.keepuneat.click | Yes | Yes | Yes | Yes | Yes |
