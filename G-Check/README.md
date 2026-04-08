# g-check — Class 7 Gut Check

Jenkins CI/CD pipeline deploying Vandelay Industries infrastructure on AWS via Terraform.

## What This Is

A Declarative Jenkins pipeline that:
1. Checks out this repo on every GitHub push (webhook trigger)
2. Runs `terraform init → validate → plan`
3. Pauses for human approval
4. Runs `terraform apply` using a saved plan
5. Runs smoke tests (HTTP 200 on app URL)
6. Runs gate tests (Secrets Manager, IAM role, RDS network)
7. Archives all results as build artifacts

## Infrastructure

| Resource | Details |
|---|---|
| App | Flask on EC2 t3.micro, behind ALB + CloudFront |
| Domain | `app.keepuneat.click` (HTTPS via ACM) |
| Database | RDS MySQL db.t3.micro, private subnets only |
| Secrets | AWS Secrets Manager with automatic rotation |
| WAF | Regional (ALB) + CloudFront scope |
| CI/CD | Jenkins on EC2 t3.medium, SSM access only (no SSH) |
| TF Backend | S3 (`class7-armagaggeon-tf-bucket`) |

## Repo Layout

```
.
├── Jenkinsfile             # Declarative pipeline — 10 stages
├── *.tf                    # Terraform — 26 files, ~121 resources
├── user_data.sh            # App EC2 bootstrap (Flask + Python)
├── jenkins_user_data.sh    # Jenkins EC2 bootstrap (auto-plugins, credentials, job)
├── python/
│   ├── gate_secrets_and_role.sh
│   ├── gate_network_db.sh
│   └── run_all_gates.sh
└── _deliverables/
    ├── SUBMISSION.md
    └── screenshots/
```

## Prerequisites

```bash
# Required in terraform.tfvars (gitignored):
db_password        = "..."
my_ip              = "x.x.x.x/32"
sns_email_endpoint = "you@example.com"

# Required Jenkins credentials:
# - vandelay-db-password  (auto-created from Secrets Manager on boot)
# - github-creds          (GitHub PAT — add manually)
```

## Run the Pipeline

```bash
# Deploy
git push origin main   # webhook fires → Build starts automatically

# Destroy
# Jenkins UI → Build with Parameters → DESTROY=true, AUTO_APPROVE=true
```
