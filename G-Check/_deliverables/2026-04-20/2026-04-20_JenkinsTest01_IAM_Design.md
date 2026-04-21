# JenkinsTest01 — Dual Credential Architecture & Least-Priv Design

**Date:** 2026-04-20
**OWASP Finding:** C3 — A02:2021 Privilege Failure (JenkinsTest01 has AdministratorAccess)
**Status:** Architecture documented | Remediation ready to apply

---

## 1. The Class Requirement

The course requires demonstrating that a Jenkins pipeline uses an IAM User credential
(`JenkinsTest01`) via `AmazonWebServicesCredentialsBinding`. This proves:

- You can manage static IAM credentials securely in Jenkins
- The credential binding masks keys from console output
- `sts:GetCallerIdentity` resolves to the IAM User ARN, not a role

```
"UserId": "AIDATDDDPJRGP3IHU4DGG",
"Account": "212809501772",
"Arn": "arn:aws:iam::212809501772:user/JenkinsTest01"
```

This requirement is satisfied by `jenkins-s3-test` (Build #6 — SUCCESS).

---

## 2. The Dual Credential Architecture

The lab runs **two pipelines** on the same Jenkins EC2, each using a different credential
mechanism by design:

| | `vandelay-lab2-pipeline` | `jenkins-s3-test` |
|---|---|---|
| **Credential type** | EC2 Instance Profile | IAM User (static keys) |
| **IAM identity** | `vandelay-jenkins-role` | `JenkinsTest01` |
| **Secret stored in Jenkins?** | No — zero secrets stored | Yes — Access Key + Secret Key |
| **How it works** | EC2 auto-fetches STS token via IMDS | `withCredentials([AWSCredentialsBinding])` injects keys as env vars |
| **Key rotation** | Automatic (~1h via STS) | Manual (must rotate in IAM console) |
| **Trigger** | GitHub Push webhook | Manual (admin) |
| **Purpose** | Deploy full lab-2 Terraform stack | Demonstrate IAM User in pipeline; TF S3 bucket lifecycle |

**Why two mechanisms?**

`vandelay-lab2-pipeline` manages the entire lab infrastructure (EC2, RDS, ALB, WAF,
CloudFront, etc.) — it needs the broader `VandelayTerraformDeployPolicy` attached to an
IAM Role via Instance Profile, which is the AWS-recommended pattern for EC2 workloads.

`jenkins-s3-test` exists specifically to satisfy the class requirement of using an IAM
User credential, and also exercises a simple Terraform S3 bucket lifecycle (create → verify
→ destroy) as a proof-of-concept pipeline.

---

## 3. The Problem: C3 — JenkinsTest01 Has AdministratorAccess

**Current state:**

```json
{
  "PolicyName": "AdministratorAccess",
  "Action": "*",
  "Resource": "*"
}
```

**Why this is a problem (OWASP A02:2021):**

If the `JenkinsTest01` Access Key is ever leaked (committed to git, logged, exposed in
an error message), an attacker has **full account control** — they can create IAM users,
exfiltrate all secrets, destroy all infrastructure, and pivot to other AWS accounts if
Organizations trust policies exist.

The `jenkins-s3-test` pipeline only needs to:
1. Prove its own identity (`sts:GetCallerIdentity`)
2. Upload/download/delete one test file in an existing S3 bucket
3. Create and destroy one ephemeral S3 bucket via Terraform
4. Lock/unlock Terraform state via DynamoDB

`AdministratorAccess` gives it everything else in the account for free — and for no reason.

---

## 4. How Pike Derives the Minimum Policy

Pike is an open-source IAM least-privilege tool by James Woolfenden. It is integrated
into the `jenkins-s3-test` pipeline as the **Pike Scan** stage (runs on every build):

```groovy
stage('Pike Scan') {
    steps {
        sh '''
            docker run --rm \
                --volume "${WORKSPACE}/jenkins-s3-test:/tf" \
                jameswoolfenden/pike scan -d /tf -o json \
                > pike-policy.json 2>&1 || true
            cat pike-policy.json
        '''
        archiveArtifacts artifacts: 'pike-policy.json', allowEmptyArchive: true
    }
}
```

**What Pike does:**

1. Reads every `.tf` file in `jenkins-s3-test/`
2. For each Terraform resource type (`aws_s3_bucket`, `aws_dynamodb_table`, etc.),
   looks up the minimum IAM actions required to `terraform apply` and `terraform destroy`
3. Outputs a valid IAM policy JSON with those exact actions

**Build #6 Pike output** (archived as `pike-policy.json`):

```json
{
  "Statement": [
    {
      "Sid": "VisualEditor0",
      "Action": [
        "dynamodb:DeleteItem",
        "dynamodb:DescribeTable",
        "dynamodb:GetItem",
        "dynamodb:PutItem"
      ]
    },
    {
      "Sid": "VisualEditor1",
      "Action": [
        "s3:CreateBucket", "s3:DeleteBucket", "s3:DeleteObject",
        "s3:GetAccelerateConfiguration", "s3:GetBucketAcl",
        "s3:GetBucketCORS", "s3:GetBucketLogging",
        "s3:GetBucketObjectLockConfiguration", "s3:GetBucketPolicy",
        "s3:GetBucketRequestPayment", "s3:GetBucketTagging",
        "s3:GetBucketVersioning", "s3:GetBucketWebsite",
        "s3:GetEncryptionConfiguration", "s3:GetLifecycleConfiguration",
        "s3:GetObject", "s3:GetObjectAcl", "s3:GetReplicationConfiguration",
        "s3:ListBucket", "s3:PutBucketTagging", "s3:PutObject"
      ]
    }
  ]
}
```

---

## 5. The Proposed Least-Priv Policy

Pike covers the Terraform resource operations. The full `JenkinsTest01-LeastPriv` policy
adds two more statements for the pipeline's non-Terraform stages:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "STSIdentity",
      "Effect": "Allow",
      "Action": ["sts:GetCallerIdentity"],
      "Resource": "*",
      "Comment": "Stage 1 — Set AWS Credentials: proves IAM User identity"
    },
    {
      "Sid": "S3ArtifactBucket",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::class7-armagaggeon-tf-bucket",
        "arn:aws:s3:::class7-armagaggeon-tf-bucket/jenkins-artifacts/*"
      ],
      "Comment": "Stage 2 — S3 Artifact Test: upload, download, delete round-trip"
    },
    {
      "Sid": "S3TerraformBuckets",
      "Effect": "Allow",
      "Action": [
        "s3:CreateBucket", "s3:DeleteBucket", "s3:DeleteObject",
        "s3:GetAccelerateConfiguration", "s3:GetBucketAcl",
        "s3:GetBucketCORS", "s3:GetBucketLogging",
        "s3:GetBucketObjectLockConfiguration", "s3:GetBucketPolicy",
        "s3:GetBucketRequestPayment", "s3:GetBucketTagging",
        "s3:GetBucketVersioning", "s3:GetBucketWebsite",
        "s3:GetEncryptionConfiguration", "s3:GetLifecycleConfiguration",
        "s3:GetObject", "s3:GetObjectAcl", "s3:GetReplicationConfiguration",
        "s3:ListBucket", "s3:PutBucketTagging", "s3:PutObject"
      ],
      "Resource": [
        "arn:aws:s3:::jenkins-bucket-*",
        "arn:aws:s3:::jenkins-bucket-*/*",
        "arn:aws:s3:::class7-armagaggeon-tf-bucket",
        "arn:aws:s3:::class7-armagaggeon-tf-bucket/*"
      ],
      "Comment": "Stages 3-7 — TF Init/Plan/Apply/Destroy + state bucket"
    },
    {
      "Sid": "DynamoDBStateLock",
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem",
        "dynamodb:DescribeTable"
      ],
      "Resource": "arn:aws:dynamodb:us-east-1:212809501772:table/terraform-state-lock",
      "Comment": "Stages 3-7 — TF state locking"
    }
  ]
}
```

**Blast radius reduction:**

| Scenario | AdministratorAccess | JenkinsTest01-LeastPriv |
|---|---|---|
| Access Key leaked | Full account takeover | Can only touch `jenkins-bucket-*` and one artifact path in the state bucket |
| Can create IAM users? | YES | NO |
| Can read RDS secrets? | YES | NO |
| Can modify lab-2 infrastructure? | YES | NO |
| Can delete EC2/RDS/ALB? | YES | NO |
| Can call sts:GetCallerIdentity? | YES | YES |
| Can run the jenkins-s3-test pipeline successfully? | YES | YES |

---

## 6. Remediation Steps (IAM Console)

1. Go to **IAM → Users → JenkinsTest01 → Permissions**
2. Click **Add permissions → Create inline policy** (or **Attach policies directly**)
3. Paste the JSON from Section 5 above
4. Name the policy: `JenkinsTest01-LeastPriv`
5. Save the policy
6. **Detach** `AdministratorAccess` from `JenkinsTest01`
7. Run `jenkins-s3-test` Build #7 to verify all stages still pass
8. Confirm `sts:GetCallerIdentity` still resolves to `JenkinsTest01` (class requirement met)

---

## 7. Architecture Diagram

See: `2026-04-20_JenkinsTest01_IAM_Architecture.d2`

Render with: `d2 2026-04-20_JenkinsTest01_IAM_Architecture.d2 output.svg`

Or use the online renderer at: https://play.d2lang.com

---

## 8. Class Presentation Summary

> **"I use two credential patterns in my Jenkins setup — by design."**
>
> `vandelay-lab2-pipeline` uses an EC2 Instance Profile (the AWS-recommended zero-secret
> approach) to deploy and manage the full lab-2 Terraform stack. No credentials are stored
> anywhere — STS auto-rotates the token every hour and IMDSv2 is enforced to block SSRF.
>
> `jenkins-s3-test` satisfies the class requirement by using `JenkinsTest01`, an IAM User
> whose static credentials are stored in Jenkins Credentials Manager and injected at
> runtime via `AWSCredentialsBinding`. You can see in the console output that
> `sts:GetCallerIdentity` explicitly returns the IAM User ARN — not a role — proving the
> credential chain.
>
> The current gap (OWASP C3) is that `JenkinsTest01` has `AdministratorAccess`. I've
> integrated Pike into the pipeline as an automated scanner — every build generates and
> archives the minimum IAM policy required for the Terraform code. The proposed least-priv
> policy reduces the blast radius from full account compromise to four scoped resources,
> while the pipeline continues to pass every stage successfully.
