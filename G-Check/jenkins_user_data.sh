#!/bin/bash
# =============================================================================
# Jenkins Bootstrap — Amazon Linux 2023
#
# What this does (fully automated — no manual wizard clicks needed):
#   0. Enable 2 GB swap (prevents OOM on t3.medium during heavy bootstrap)
#   1. Mount persistent EBS volume (survives EC2 replacement)
#   2. Install Java 21, Jenkins LTS, Terraform, Git, Docker
#   3. Skip Jenkins setup wizard
#   4. Pre-install pipeline plugins via jenkins-plugin-cli
#   5. Drop init.groovy.d scripts to create credentials + pipeline job
#   6. Start Jenkins and wait for ready
#
# After apply, Jenkins is at: http://<jenkins_public_ip>:8080
# Login: admin / <initialAdminPassword in /var/log/jenkins-setup.log>
# The pipeline job "vandelay-lab2-pipeline" is auto-created.
# =============================================================================

set -euo pipefail

LOG=/var/log/jenkins-setup.log
exec > >(tee -a "$LOG") 2>&1
echo "=== Jenkins bootstrap started $(date) ==="

########################################
# 0. Swap — 2 GB swap file to prevent OOM during heavy bootstrap
# AL2023 t3.medium ships with 0 swap; plugin install + Docker exhaust 4 GB RAM.
########################################

if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "=== Swap enabled: $(free -h | grep Swap) ==="
fi

########################################
# 1. Mount persistent EBS volume
# Device appears as /dev/nvme1n1 on t3 (NVMe) or /dev/xvdf on older types
########################################

for i in $(seq 1 12); do
  if [ -b /dev/nvme1n1 ]; then
    DEVICE=/dev/nvme1n1
    break
  elif [ -b /dev/xvdf ]; then
    DEVICE=/dev/xvdf
    break
  fi
  sleep 5
done

if [ -n "${DEVICE:-}" ]; then
  if ! blkid "$DEVICE" | grep -q "jenkins-data"; then
    mkfs.ext4 -L jenkins-data "$DEVICE"
  fi
  mkdir -p /var/lib/jenkins
  mount -L jenkins-data /var/lib/jenkins
  if ! grep -q "jenkins-data" /etc/fstab; then
    echo "LABEL=jenkins-data /var/lib/jenkins ext4 defaults,nofail 0 2" >> /etc/fstab
  fi
  echo "EBS volume mounted at /var/lib/jenkins"
fi

########################################
# 2. Install Jenkins, Java 21, Terraform, Git, Docker
########################################

dnf update -y

wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key

# Java 21 — Jenkins LTS requirement (Java 17 EOL Mar 2026)
dnf install -y java-21-amazon-corretto-headless

dnf install -y jenkins git

# Terraform
dnf install -y dnf-plugins-core
dnf config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
dnf install -y terraform

# Docker — required for Rover Graph pipeline stage
# AL2023 ships docker via the standard repo
dnf install -y docker
systemctl enable docker
systemctl start docker
# Allow jenkins user to run docker without sudo
usermod -aG docker jenkins
echo "=== Docker installed: $(docker --version) ==="

# Python 3.12 — AL2023 default (python3) resolves to 3.9 which is EOL (Oct 2025).
# Explicitly install 3.12, set it as the system default, then install boto3.
dnf install -y python3.12 python3.12-pip
alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 20
alternatives --set python3 /usr/bin/python3.12
ln -sf /usr/bin/python3.12 /usr/local/bin/python3
ln -sf /usr/bin/python3.12 /usr/bin/python
/usr/bin/python3.12 -m pip install --quiet boto3 botocore
# awscli2 package shebang is /usr/bin/python3 — after alternatives change it
# now points to 3.12 where awscli is not installed. Pin shebang to python3.9.
sed -i '1s|.*|#!/usr/bin/python3.9 -s|' /usr/bin/aws
echo "=== Python: $(python3 --version) ==="
echo "=== AWS CLI: $(aws --version) ==="

echo "=== Package installation complete ==="

########################################
# 3. Skip setup wizard
# Write the version marker files Jenkins checks on first boot.
# Without these, Jenkins blocks in "Getting Started" wizard.
########################################

mkdir -p /var/lib/jenkins
JENKINS_VERSION=$(java -jar /usr/share/java/jenkins.war --version 2>/dev/null | head -1 || echo "2.0")
echo "$JENKINS_VERSION" > /var/lib/jenkins/jenkins.install.InstallUtil.lastExecVersion
echo "$JENKINS_VERSION" > /var/lib/jenkins/jenkins.install.UpgradeWizard.state

########################################
# 4. Pre-install plugins via Plugin Installation Manager JAR
# jenkins-plugin-cli binary is NOT available on AL2023 + Jenkins LTS.
# We download the JAR directly and run it with java — this always works.
########################################

PLUGIN_DIR=/var/lib/jenkins/plugins
mkdir -p "$PLUGIN_DIR"

# Download Plugin Installation Manager Tool JAR
PIM_JAR=/usr/local/lib/jenkins-plugin-manager.jar
if [ ! -f "$PIM_JAR" ]; then
  echo "=== Downloading Plugin Installation Manager JAR ==="
  curl -sL -o "$PIM_JAR" \
    "https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/2.12.15/jenkins-plugin-manager-2.12.15.jar"
fi

# Top-level plugins — transitive deps are resolved automatically.
# This is the full set currently installed on the running Jenkins instance.
PLUGINS=(
  # Pipeline suite
  workflow-aggregator
  pipeline-stage-view
  pipeline-graph-analysis
  pipeline-aws
  # SCM + GitHub
  git
  github
  github-branch-source
  github-oauth
  github-pullrequest
  github-checks
  git-push
  git-tag-message
  # Credentials
  credentials-binding
  plain-credentials
  aws-credentials
  aws-secrets-manager-secret-source
  # AWS integrations
  ec2
  aws-java-sdk
  configuration-as-code
  configuration-as-code-secret-ssm
  # Blue Ocean
  blueocean-web
  blueocean-rest
  blueocean-pipeline-api-impl
  blueocean-pipeline-scm-api
  blueocean-github-pipeline
  # DevSecOps
  snyk-security-scanner
  sonar
  # Infrastructure-as-Code
  terraform
  # Kubernetes (future use)
  kubernetes
  kubernetes-credentials
  kubernetes-cli
  # Build utilities
  timestamper
  ansicolor
  ws-cleanup
  build-timeout
  copyartifact
  htmlpublisher
  # Auth + security
  matrix-auth
  authorize-project
  # Misc / UI
  dark-theme
  mailer
  junit
  git-forensics
)

echo "=== Installing plugins via Plugin Installation Manager JAR ==="
java -jar "$PIM_JAR" \
  --war /usr/share/java/jenkins.war \
  --plugin-download-directory "$PLUGIN_DIR" \
  --plugins "${PLUGINS[*]}" \
  && echo "=== Plugin install complete ===" \
  || echo "WARNING: plugin-manager encountered errors — check /var/log/jenkins-setup.log"

########################################
# 5. Create init.groovy.d scripts
# These run once on the first Jenkins startup before any builds.
########################################

mkdir -p /var/lib/jenkins/init.groovy.d

# --- 5a. Plugin safety-net --------------------------------------------------
# Runs after Jenkins starts. Installs any plugins still missing (e.g. if the
# pre-install JAR step partially failed) and restarts Jenkins once if needed.

cat > /var/lib/jenkins/init.groovy.d/00-install-plugins.groovy << 'GROOVY'
import jenkins.model.Jenkins
import hudson.PluginManager
import hudson.util.VersionNumber

def required = [
  'workflow-aggregator', 'pipeline-stage-view', 'pipeline-graph-analysis', 'pipeline-aws',
  'git', 'github', 'github-branch-source', 'github-oauth', 'github-pullrequest',
  'github-checks', 'git-push', 'git-tag-message',
  'credentials-binding', 'plain-credentials', 'aws-credentials',
  'aws-secrets-manager-secret-source', 'ec2', 'aws-java-sdk',
  'configuration-as-code', 'configuration-as-code-secret-ssm',
  'blueocean-web', 'blueocean-rest', 'blueocean-pipeline-api-impl',
  'blueocean-pipeline-scm-api', 'blueocean-github-pipeline',
  'snyk-security-scanner', 'sonar', 'terraform', 'kubernetes',
  'kubernetes-credentials', 'kubernetes-cli',
  'copyartifact', 'htmlpublisher', 'matrix-auth', 'authorize-project',
  'dark-theme', 'mailer', 'junit', 'git-forensics'
]

def pm = Jenkins.get().pluginManager
def uc = Jenkins.get().updateCenter

uc.updateAllSites()

def missing = required.findAll { name ->
  pm.getPlugin(name) == null
}

if (missing.isEmpty()) {
  println "=== All required plugins already installed ==="
  return
}

println "=== Installing missing plugins: ${missing.join(', ')} ==="
def installed = false
missing.each { name ->
  def plugin = uc.getPlugin(name)
  if (plugin) {
    plugin.deploy(true).get()   // deploy + block until done
    installed = true
    println "  Installed: ${name}"
  } else {
    println "  WARNING: plugin not found in update center: ${name}"
  }
}

if (installed) {
  println "=== Plugin install complete — scheduling restart ==="
  Jenkins.get().safeRestart()
}
GROOVY

# --- 5b. Credentials --------------------------------------------------------
# Pulls vandelay-db-password from Secrets Manager at boot time.
# Snyk stubs have placeholder values — fill them in Jenkins UI before Snyk session.

cat > /var/lib/jenkins/init.groovy.d/01-credentials.groovy << 'GROOVY'
import jenkins.model.Jenkins
import com.cloudbees.plugins.credentials.*
import com.cloudbees.plugins.credentials.common.*
import com.cloudbees.plugins.credentials.domains.*
import com.cloudbees.plugins.credentials.impl.*
import org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl
import hudson.util.Secret

def jenkins = Jenkins.get()
def domain  = Domain.global()
def store   = SystemCredentialsProvider.getInstance().getStore()

def addSecret = { id, desc, value ->
  def existing = store.getCredentials(domain).find { it.id == id }
  if (!existing) {
    store.addCredentials(domain, new StringCredentialsImpl(
      CredentialsScope.GLOBAL, id, desc, Secret.fromString(value)
    ))
    println "Created credential: ${id}"
  } else {
    println "Credential already exists (skipped): ${id}"
  }
}

// Pull RDS password from Secrets Manager so the pipeline can run TF plan/apply
// on the very first build without any manual credential entry.
def rawSecret = ['bash', '-c',
  'aws secretsmanager get-secret-value --secret-id lab/rds/mysql --query SecretString --output text 2>/dev/null'
].execute().text.trim()

def dbPassword = 'REPLACE_ME_WITH_DB_PASSWORD'
if (rawSecret && rawSecret != '') {
  try {
    def parsed = new groovy.json.JsonSlurper().parseText(rawSecret)
    dbPassword = parsed.password ?: dbPassword
    println "DB password loaded from Secrets Manager"
  } catch (e) {
    println "Could not parse Secrets Manager response: ${e.message}"
  }
}

addSecret('vandelay-db-password',    'RDS master password (TF_VAR_db_password)',            dbPassword)
addSecret('snyk-api-token-string',   'Snyk API token — Secret Text for CLI stage',          'REPLACE_WITH_SNYK_TOKEN')
addSecret('snyk-org-slug',           'Snyk org slug — visible in Snyk UI URL',              'REPLACE_WITH_SNYK_ORG')

// GitHub credential — Username/Password with PAT (repo + workflow scopes)
def ghExisting = store.getCredentials(domain).find { it.id == 'github-creds' }
if (!ghExisting) {
  store.addCredentials(domain, new UsernamePasswordCredentialsImpl(
    CredentialsScope.GLOBAL, 'github-creds', 'GitHub PAT for webhook + checkout',
    'NRD808Sequence', 'REPLACE_WITH_GITHUB_PAT'
  ))
  println "Created credential: github-creds"
}

jenkins.save()
println "=== Credentials init complete ==="
GROOVY

# --- 5b. Pipeline job -------------------------------------------------------
# Creates "vandelay-lab2-pipeline" from SCM — GitHub + Jenkinsfile path.

cat > /var/lib/jenkins/init.groovy.d/02-pipeline-job.groovy << 'GROOVY'
import jenkins.model.Jenkins
import org.jenkinsci.plugins.workflow.job.WorkflowJob
import org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition
import hudson.plugins.git.GitSCM
import hudson.plugins.git.BranchSpec
import hudson.plugins.git.UserRemoteConfig
import hudson.plugins.git.extensions.impl.CloneOption
import com.coravy.hudson.plugins.github.GithubProjectProperty

def jenkins = Jenkins.get()
def jobName = 'vandelay-lab2-pipeline'

if (jenkins.getItem(jobName)) {
  println "Job '${jobName}' already exists — skipping"
  return
}

def scm = new GitSCM(
  [new UserRemoteConfig('https://github.com/NRD808Sequence/DevOps.git', null, null, 'github-creds')],
  [new BranchSpec('*/main')],
  null, null, []
)

def flowDef = new CpsScmFlowDefinition(scm, 'G-Check/Jenkinsfile')
flowDef.lightweight = true

def job = jenkins.createProject(WorkflowJob, jobName)
job.definition = flowDef
job.addProperty(new GithubProjectProperty('https://github.com/NRD808Sequence/DevOps/'))

job.save()
jenkins.save()
println "=== Pipeline job '${jobName}' created ==="
GROOVY

########################################
# 6. Fix ownership and start Jenkins
########################################

chown -R jenkins:jenkins /var/lib/jenkins

systemctl enable jenkins
systemctl start jenkins

# Wait up to 5 minutes for Jenkins to be ready
echo "=== Waiting for Jenkins to be ready ==="
timeout 300 bash -c '
  until curl -sf http://localhost:8080/login > /dev/null 2>&1; do
    sleep 5
  done
'

INIT_PASS=$(cat /var/lib/jenkins/secrets/initialAdminPassword 2>/dev/null || echo "Password file not found — may have used existing EBS data")
echo "=== Initial admin password: ${INIT_PASS} ==="
echo "=== Jenkins bootstrap complete $(date) ==="

########################################
# 7. Binary verification — confirm all required tools are present
########################################

echo ""
echo "=== Binary Verification ==="
echo "---"
java        -version 2>&1 | head -1
jenkins     --version 2>/dev/null       || echo "Jenkins: service-based (check systemctl status jenkins)"
terraform   version   | head -1
docker      --version
python3     --version
aws         --version
git         --version
echo "---"
echo "=== All binaries confirmed ==="
echo ""
echo "=== Next steps ==="
echo "  1. Login: http://<public-ip>:8080  user: admin  pass: see above"
echo "  2. Install Snyk plugin: Manage Jenkins → Plugins → Available → Snyk Security"
echo "  3. Add Snyk API token to 'snyk-api-token' credential (Snyk Plugin type)"
echo "  4. Add GitHub PAT to 'github-creds' credential"
echo "  5. Run pipeline: vandelay-lab2-pipeline → Build Now"
