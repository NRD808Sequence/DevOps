#!/usr/bin/env bash
# =============================================================================
# health_check.sh  —  Vandelay Lab-2 Infrastructure Health Check
#
# Checks:
#   1. CloudFront  — HTTPS returns HTTP 200 (app + root)
#   2. WAF origin cloaking — direct ALB returns 403 (NOT 200)
#   3. EC2 app     — HTTP direct to EC2 IP returns 200
#   4. Jenkins UI  — port 8080 returns a response (login page / 403)
#   5. RDS DNS     — endpoint resolves (not publicly reachable is expected)
#   6. AWS gates   — runs run_all_gates.sh (secrets + role + network checks)
#
# Usage:
#   # Auto-detect from terraform output (run from lab-2/):
#   cd lab-2 && ./python/health_check.sh
#
#   # Override any value via env:
#   CF_URL=https://app.keepuneat.click \
#   EC2_IP=1.2.3.4 \
#   JENKINS_IP=5.6.7.8 \
#   ALB_DNS=myalb.elb.amazonaws.com \
#   RDS_ENDPOINT=mydb.rds.amazonaws.com \
#   ./python/health_check.sh
#
# Exit codes:
#   0 = all checks passed
#   1 = one or more checks failed
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass()  { echo -e "${GREEN}  PASS${NC}  $*"; }
fail()  { echo -e "${RED}  FAIL${NC}  $*"; FAILURES=$((FAILURES+1)); }
warn()  { echo -e "${YELLOW}  WARN${NC}  $*"; WARNINGS=$((WARNINGS+1)); }
info()  { echo -e "  INFO  $*"; }
banner(){ echo -e "\n${YELLOW}>>> $*${NC}"; }

FAILURES=0
WARNINGS=0

# ---------------------------------------------------------------------------
# Resolve endpoints — prefer env overrides, fall back to terraform output
# ---------------------------------------------------------------------------
banner "Resolving endpoints"

tf_output() {
  terraform -chdir="$TF_DIR" output -raw "$1" 2>/dev/null || echo ""
}

CF_URL="${CF_URL:-$(tf_output vandelay_app_url_via_cloudfront)}"
EC2_IP="${EC2_IP:-$(tf_output ec2_public_ip)}"
JENKINS_IP="${JENKINS_IP:-$(tf_output jenkins_public_ip)}"
ALB_DNS="${ALB_DNS:-$(tf_output vandelay_rds_endpoint | sed 's/:.*//')}"  # reuse rds host just for region check
RDS_ENDPOINT="${RDS_ENDPOINT:-$(tf_output rds_endpoint)}"
INSTANCE_ID="${INSTANCE_ID:-$(tf_output ec2_instance_id)}"
SECRET_ID="${SECRET_ID:-$(tf_output secret_name)}"
DB_ID="${DB_ID:-$(tf_output rds_identifier)}"
REGION="${REGION:-us-east-1}"

# Derive ALB DNS from CloudFront distribution if not set
if [[ -z "${ALB_DNS:-}" ]]; then
  ALB_DNS="$(terraform -chdir="$TF_DIR" output 2>/dev/null | grep -i alb | grep elb.amazonaws.com | head -1 | sed 's/.*= "//' | sed 's/".*//' || echo "")"
fi

info "CloudFront  : $CF_URL"
info "EC2 IP      : $EC2_IP"
info "Jenkins IP  : $JENKINS_IP"
info "RDS endpoint: $RDS_ENDPOINT"
info "Instance ID : $INSTANCE_ID"
info "Secret ID   : $SECRET_ID"
info "DB ID       : $DB_ID"
info "Region      : $REGION"

# ---------------------------------------------------------------------------
# Helper: HTTP status check
# ---------------------------------------------------------------------------
http_status() {
  local url="$1"
  local expected="$2"
  local label="$3"
  local extra_args="${4:-}"

  local status
  # shellcheck disable=SC2086
  status=$(curl -s -o /dev/null -w "%{http_code}" \
    --connect-timeout 8 \
    --max-time 15 \
    $extra_args \
    "$url" 2>/dev/null || echo "000")

  if [[ "$status" == "$expected" ]]; then
    pass "$label — HTTP $status (expected $expected)"
  else
    fail "$label — HTTP $status (expected $expected) @ $url"
  fi
}

# Same but accepts any of a list of codes
http_status_any() {
  local url="$1"
  shift
  local expected_codes=("$@")
  local last_arg="${expected_codes[-1]}"
  # last arg is the label if it doesn't look like a code
  local label=""
  if ! [[ "$last_arg" =~ ^[0-9]+$ ]]; then
    label="$last_arg"
    unset 'expected_codes[-1]'
  fi

  local status
  status=$(curl -s -o /dev/null -w "%{http_code}" \
    --connect-timeout 8 \
    --max-time 15 \
    "$url" 2>/dev/null || echo "000")

  for code in "${expected_codes[@]}"; do
    if [[ "$status" == "$code" ]]; then
      pass "${label} — HTTP $status"
      return 0
    fi
  done
  fail "${label} — HTTP $status (expected one of: ${expected_codes[*]}) @ $url"
  return 1
}

# ---------------------------------------------------------------------------
# 1. CloudFront health
# ---------------------------------------------------------------------------
banner "1 / 6  CloudFront HTTPS"

if [[ -n "$CF_URL" ]]; then
  http_status "$CF_URL/" "200" "CF root /"
  http_status "$CF_URL/health" "200" "CF /health"
  http_status "$CF_URL/list" "200" "CF /list"
else
  warn "CF_URL not resolved — skipping CloudFront checks"
fi

# ---------------------------------------------------------------------------
# 2. Origin cloaking — direct ALB must NOT return 200
# ---------------------------------------------------------------------------
banner "2 / 6  Origin Cloaking (direct ALB must be blocked)"

# Try to get ALB DNS from TF state directly
ALB_DNS_TF="$(terraform -chdir="$TF_DIR" output 2>/dev/null \
  | grep 'vandelay-alb01' \
  | grep 'elb.amazonaws.com' \
  | head -1 \
  | sed 's/.*"\(.*elb.amazonaws.com\)".*/\1/' || echo "")"

if [[ -n "$ALB_DNS_TF" ]]; then
  status=$(curl -s -o /dev/null -w "%{http_code}" \
    --connect-timeout 8 --max-time 12 \
    "http://$ALB_DNS_TF/" 2>/dev/null || echo "000")
  if [[ "$status" == "403" || "$status" == "000" ]]; then
    pass "Direct ALB blocked — HTTP $status (origin cloaking active)"
  elif [[ "$status" == "200" ]]; then
    fail "Direct ALB returned 200 — origin cloaking may be broken @ http://$ALB_DNS_TF/"
  else
    warn "Direct ALB returned HTTP $status — verify cloaking manually @ http://$ALB_DNS_TF/"
  fi
else
  warn "Could not resolve ALB DNS from state — skipping origin cloaking check"
fi

# ---------------------------------------------------------------------------
# 3. EC2 direct access
# ---------------------------------------------------------------------------
banner "3 / 6  EC2 App (direct)"

if [[ -n "$EC2_IP" ]]; then
  http_status "http://$EC2_IP/" "200" "EC2 direct /"
  http_status "http://$EC2_IP/health" "200" "EC2 /health"
else
  warn "EC2_IP not resolved — skipping EC2 direct checks"
fi

# ---------------------------------------------------------------------------
# 4. Jenkins UI
# ---------------------------------------------------------------------------
banner "4 / 6  Jenkins UI (port 8080)"

if [[ -n "$JENKINS_IP" ]]; then
  # Jenkins login page returns 200 (not yet configured) or 403 (if secured)
  status=$(curl -s -o /dev/null -w "%{http_code}" \
    --connect-timeout 8 --max-time 15 \
    "http://$JENKINS_IP:8080/" 2>/dev/null || echo "000")

  if [[ "$status" == "200" || "$status" == "403" ]]; then
    pass "Jenkins UI reachable — HTTP $status @ http://$JENKINS_IP:8080/"
  elif [[ "$status" == "000" ]]; then
    fail "Jenkins UI unreachable (timeout/refused) @ http://$JENKINS_IP:8080/"
    warn "If Jenkins just started, wait ~2 min for bootstrap to complete"
  else
    warn "Jenkins UI returned HTTP $status — may still be starting"
  fi
else
  warn "JENKINS_IP not resolved — skipping Jenkins check"
fi

# ---------------------------------------------------------------------------
# 5. RDS DNS resolution
# ---------------------------------------------------------------------------
banner "5 / 6  RDS DNS Resolution"

if [[ -n "$RDS_ENDPOINT" ]]; then
  if host "$RDS_ENDPOINT" >/dev/null 2>&1 || nslookup "$RDS_ENDPOINT" >/dev/null 2>&1; then
    pass "RDS DNS resolves — $RDS_ENDPOINT"
    # Confirm NOT publicly reachable (connection should be refused on 3306)
    if ! nc -z -w 4 "$RDS_ENDPOINT" 3306 2>/dev/null; then
      pass "RDS port 3306 not reachable from internet (private subnet confirmed)"
    else
      fail "RDS port 3306 reachable from internet — verify PubliclyAccessible=false"
    fi
  else
    fail "RDS DNS does not resolve — $RDS_ENDPOINT"
  fi
else
  warn "RDS_ENDPOINT not resolved — skipping RDS check"
fi

# ---------------------------------------------------------------------------
# 6. AWS Gate scripts (secrets + role + network)
# ---------------------------------------------------------------------------
banner "6 / 6  AWS Gate Scripts"

if [[ -n "$INSTANCE_ID" && -n "$SECRET_ID" && -n "$DB_ID" ]]; then
  if [[ -f "$SCRIPT_DIR/run_all_gates.sh" ]]; then
    pushd "$SCRIPT_DIR" > /dev/null
    set +e
    REGION="$REGION" \
    INSTANCE_ID="$INSTANCE_ID" \
    SECRET_ID="$SECRET_ID" \
    DB_ID="$DB_ID" \
    REQUIRE_ROTATION=false \
    CHECK_PRIVATE_SUBNETS=false \
    OUT_JSON="gate_result.json" \
    bash ./run_all_gates.sh
    gate_rc=$?
    set -e
    popd > /dev/null

    if [[ "$gate_rc" -eq 0 ]]; then
      pass "Gate scripts passed (exit $gate_rc)"
    else
      fail "Gate scripts failed (exit $gate_rc)"
    fi
  else
    warn "run_all_gates.sh not found at $SCRIPT_DIR — skipping"
  fi
else
  warn "INSTANCE_ID / SECRET_ID / DB_ID not resolved — skipping gate scripts"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "=============================================="
if [[ "$FAILURES" -eq 0 && "$WARNINGS" -eq 0 ]]; then
  echo -e "${GREEN}  ALL CHECKS PASSED${NC}  (0 failures, 0 warnings)"
  exit 0
elif [[ "$FAILURES" -eq 0 ]]; then
  echo -e "${YELLOW}  PASSED WITH WARNINGS${NC}  (0 failures, $WARNINGS warnings)"
  exit 0
else
  echo -e "${RED}  HEALTH CHECK FAILED${NC}  ($FAILURES failures, $WARNINGS warnings)"
  exit 1
fi
