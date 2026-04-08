#!/bin/bash
# =============================================================================
# Jenkins Bootstrap — Amazon Linux 2023
#
# What this does (fully automated — no manual wizard clicks needed):
#   1. Mount persistent EBS volume (survives EC2 replacement)
#   2. Install Java 21, Jenkins LTS, Terraform, Git
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
# 2. Install Jenkins, Java 21, Terraform, Git
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
# 4. Pre-install plugins via jenkins-plugin-cli
# Core set for this pipeline — runs before Jenkins starts so plugins
# are present on first boot (no "restart to activate" loop).
########################################

PLUGIN_DIR=/var/lib/jenkins/plugins
mkdir -p "$PLUGIN_DIR"

PLUGINS=(
  # Pipeline core
  "workflow-aggregator"
  "pipeline-stage-view"
  "pipeline-graph-analysis"
  # SCM
  "git"
  "github"
  "github-branch-source"
  # Credentials
  "credentials"
  "credentials-binding"
  "plain-credentials"
  "aws-credentials"
  # Build options used in Jenkinsfile
  "timestamper"
  "ansicolor"
  "ws-cleanup"
  "build-timeout"
  # Snyk DevSecOps (next session)
  "snyk-security-scanner"
  # Misc
  "matrix-auth"
  "authorize-project"
)

echo "=== Installing plugins ==="
/usr/bin/jenkins-plugin-cli \
  --war /usr/share/java/jenkins.war \
  --plugin-download-directory "$PLUGIN_DIR" \
  --plugins "${PLUGINS[*]}" \
  && echo "Plugin install complete" \
  || echo "WARNING: jenkins-plugin-cli encountered errors — plugins may need manual install"

########################################
# 5. Create init.groovy.d scripts
# These run once on the first Jenkins startup before any builds.
########################################

mkdir -p /var/lib/jenkins/init.groovy.d

# --- 5a. Credentials --------------------------------------------------------
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
echo ""
echo "=== Next steps ==="
echo "  1. Login: http://<public-ip>:8080  user: admin  pass: see above"
echo "  2. Install Snyk plugin: Manage Jenkins → Plugins → Available → Snyk Security"
echo "  3. Add Snyk API token to 'snyk-api-token' credential (Snyk Plugin type)"
echo "  4. Add GitHub PAT to 'github-creds' credential"
echo "  5. Run pipeline: vandelay-lab2-pipeline → Build Now"
