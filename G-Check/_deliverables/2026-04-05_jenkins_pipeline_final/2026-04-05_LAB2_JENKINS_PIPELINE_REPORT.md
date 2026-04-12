# Lab-2 Jenkins CI/CD Pipeline — Final Evidence Report
**Date:** 2026-04-05
**Pipeline:** `vandelay-lab2-pipeline`
**Jenkins:** http://18.234.188.25:8080
**Repo:** https://github.com/NRD808Sequence/Class7ZION (branch: `main`)
**Deployable Path:** `Armageddon/lab-2/`

---

## Pipeline Outcome

| Build | Result  | Duration | Trigger              | Notes                                   |
|-------|---------|----------|----------------------|-----------------------------------------|
| #9    | FAILURE | 9:46     | CLI                  | AlreadyExists errors — orphaned state   |
| #10   | FAILURE | 0:05     | CLI                  | TF_DIR wrong default                    |
| #11   | FAILURE | 9:31     | CLI                  | AlreadyExists — imports needed          |
| #12   | FAILURE | 0:06     | CLI                  | Validation error                        |
| #13   | FAILURE | 0:06     | CLI                  | Validation error                        |
| #14   | FAILURE | 32:31    | CLI (approved)       | rotation error + AllowSNSInvoke         |
| #15   | FAILURE | 8:48     | CLI                  | rotation error                          |
| #16   | ABORTED | 18:46    | Webhook              | Aborted — stale plan (pre-import)       |
| **#17** | **SUCCESS** | **16:10** | **CLI (approved)** | **Full deploy — all gates GREEN**   |
| **#18** | **SUCCESS** | **1:49**  | **CLI**            | **Zero-change plan — all gates GREEN** |

**Two consecutive GREEN builds confirm stable pipeline and stable infrastructure.**

---

## Deployed Infrastructure (Build #17, 2026-04-05)

| Resource          | ID / Value                                                |
|-------------------|-----------------------------------------------------------|
| EC2 Instance      | `i-07be502d81275854c` (t3.micro, us-east-1a)             |
| EC2 Public IP     | `35.175.217.81`                                           |
| EC2 IAM Profile   | `vandelay-instance-profile01` → role `vandelay-ec2-role01` |
| RDS Instance      | `vandelay-rds01` (MySQL, port 3306, not public)          |
| RDS Endpoint      | `vandelay-rds01.cmrys4aosktq.us-east-1.rds.amazonaws.com` |
| Secret            | `lab/rds/mysql` (RotationEnabled=True, Lambda attached)  |
| ALB               | `vandelay-alb01` (active, internet-facing)               |
| WAF               | `vandelay-waf01` (regional, attached to ALB)             |
| CloudFront        | `E2J9Y6PVQFFAD2` (Deployed, HTTPS)                       |
| Domain            | `app.keepuneat.click` / `keepuneat.click`                |
| Jenkins Host      | `i-0ae539b167d765370` @ `18.234.188.25:8080`             |
| Jenkins IAM       | `vandelay-jenkins-profile` → `vandelay-jenkins-role`     |

---

## Gate Test Results — BUILD #17 (2026-04-05T15:28:40Z)

### Gate 1: Secrets + EC2 Role  `PASS`
```
PASS: aws sts get-caller-identity succeeded (credentials OK)
PASS: secret exists and is describable (lab/rds/mysql)
PASS: no resource policy found (OK) or not applicable
PASS: instance has IAM instance profile attached (i-07be502d81275854c)
PASS: resolved instance profile -> role (vandelay-instance-profile01 -> vandelay-ec2-role01)
NOTE: caller_arn = arn:aws:sts::[ACCOUNT_ID]:assumed-role/vandelay-jenkins-role/i-0ae539b167d765370
      (pipeline runs as Jenkins IAM role — correct)
```

### Gate 2: Network + RDS  `PASS`
```
PASS: RDS instance exists (vandelay-rds01)
PASS: RDS is not publicly accessible (PubliclyAccessible=False)
PASS: discovered DB port = 3306 (engine=mysql)
PASS: EC2 security groups resolved: sg-0733362cfff813d6e
PASS: RDS security groups resolved: sg-0371f51e450798f1a
PASS: RDS SG allows DB port 3306 from EC2 SG (SG-to-SG ingress present)
```

### Combined Badge
```
BADGE: GREEN
STATUS: PASS
Exit codes: gate1=0, gate2=0
```

---

## Gate Test Results — BUILD #18 (2026-04-05T15:30:30Z)

Same instance IDs, same GREEN result. Second consecutive clean run confirms stability.

---

## Smoke Test Evidence

```
CF  app.keepuneat.click/       → HTTP 200  ✓
CF  app.keepuneat.click/health → HTTP 200  ✓
EC2 35.175.217.81/             → HTTP 200  ✓
EC2 35.175.217.81/health       → HTTP 200  ✓
Jenkins http://18.234.188.25:8080 → HTTP 200 (login page) ✓
RDS 3306 not reachable from internet ✓
```

---

## Pipeline Stages — Build #17

| Stage                    | Status  | Notes                                    |
|--------------------------|---------|------------------------------------------|
| Checkout                 | PASS    | branch: origin/main, commit: 8b806834    |
| TF Init                  | PASS    | S3 backend: class7-armagaggeon-tf-bucket |
| TF Validate              | PASS    | No format drift                          |
| TF Plan                  | PASS    | 0 to add, 1 to change, 0 to destroy      |
| TF Plan (Destroy Preview)| SKIPPED | DESTROY=false                            |
| Approval Gate            | PASS    | Human-approved (PROCEED)                 |
| Destroy Approval Gate    | SKIPPED | DESTROY=false                            |
| TF Apply                 | PASS    | rotate_immediately drift updated         |
| TF Destroy               | SKIPPED | DESTROY=false                            |
| Extract Outputs          | PASS    | All 5 outputs resolved                   |
| Smoke Test               | PASS    | HTTP 200 on attempt 1                    |
| Gate Tests               | PASS    | BADGE: GREEN                             |
| Notify                   | PASS    | Action: DEPLOY                           |

---

## Jenkins Pipeline Configuration

- **Job:** `vandelay-lab2-pipeline`
- **Trigger:** `githubPush()` + manual build
- **SCM:** `https://github.com/NRD808Sequence/Class7ZION.git`, branch `*/main`
- **Jenkinsfile path:** `Armageddon/lab-2/Jenkinsfile`
- **TF backend key:** `class7/fineqts/armageddontf/state-key`
- **Credentials used:** `vandelay-db-password` (Secret Text, injected as `TF_VAR_db_password`)
- **Jenkins IAM role:** `vandelay-jenkins-role` with `TerraformDeployPolicy`

---

## Attached Artifacts

| File                              | Description                               |
|-----------------------------------|-------------------------------------------|
| `build17_console.txt`             | Full Build #17 console log (659 lines)    |
| `build18_console.txt`             | Full Build #18 console log               |
| `build17_gate_result.json`        | Combined gate result — Build #17          |
| `build17_gate_secrets_and_role.json` | Gate 1 detail — Build #17             |
| `build18_gate_result.json`        | Combined gate result — Build #18          |
| `build18_gate_secrets_and_role.json` | Gate 1 detail — Build #18             |
| `build18_gate_network_db.json`    | Gate 2 detail — Build #18                |
| `local_gate_secrets_and_role.json`| Local CLI re-run (2026-04-05T15:49:42Z)   |
| `local_gate_network_db.json`      | Local CLI re-run (2026-04-05T15:49:52Z)   |
| `gate_result_2026-04-05.json`     | Local combined result re-run              |

---

## Screenshot Checklist (capture in browser)

### Jenkins UI
- [ ] `http://18.234.188.25:8080/job/vandelay-lab2-pipeline/` — pipeline overview with build history (green #17, #18)
- [ ] `http://18.234.188.25:8080/job/vandelay-lab2-pipeline/17/` — Build #17 stage view (all green stages)
- [ ] `http://18.234.188.25:8080/job/vandelay-lab2-pipeline/17/console` — Build #17 console showing "BUILD SUCCEEDED" at bottom
- [ ] `http://18.234.188.25:8080/job/vandelay-lab2-pipeline/17/artifact/` — artifact list (gate JSONs + tfplan.txt)
- [ ] `http://18.234.188.25:8080/job/vandelay-lab2-pipeline/configure` — shows GitHub repo URL, Jenkinsfile path, triggers

### App Endpoints (browser)
- [ ] `https://app.keepuneat.click/` — Flask app via CloudFront (HTTP 200)
- [ ] `https://app.keepuneat.click/health` — health endpoint (HTTP 200)
- [ ] `http://35.175.217.81/` — direct EC2 access (HTTP 200)

### AWS Console (optional but strong evidence)
- [ ] EC2 console: instance `i-07be502d81275854c` running with IAM profile
- [ ] RDS console: `vandelay-rds01` available, not publicly accessible
- [ ] Secrets Manager: `lab/rds/mysql` with rotation enabled
- [ ] CloudFront: distribution `E2J9Y6PVQFFAD2` Deployed
- [ ] WAF: `vandelay-waf01` associated with ALB
- [ ] GitHub: `NRD808Sequence/Class7ZION` → Settings → Webhooks (active webhook to Jenkins)

### GitHub (webhook evidence)
- [ ] `https://github.com/NRD808Sequence/Class7ZION/settings/hooks` — active webhook, recent deliveries shown as green
