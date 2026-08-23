#!/usr/bin/env bash
# Oracle Cloud Always Free ARM is a shared leftover pool.
# Rotate availability domains until a launch succeeds.
set -uo pipefail

TF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../terraform" && pwd)"
LOG="${TF_DIR}/../arm-retry.log"
ADS=(
  "uKkk:EU-FRANKFURT-1-AD-1"
  "uKkk:EU-FRANKFURT-1-AD-2"
  "uKkk:EU-FRANKFURT-1-AD-3"
)
SLEEP_SECONDS=300

cd "$TF_DIR" || exit 1
log() { echo "[$(date -Is)] $*" | tee -a "$LOG"; }

if terraform state list 2>/dev/null | grep -q 'oci_core_instance.soc_core'; then
  log "soc-core already exists. Exiting."
  exit 0
fi

attempt=0
while true; do
  for ad in "${ADS[@]}"; do
    attempt=$((attempt + 1))
    log "Attempt ${attempt}: ${ad}"

    if terraform apply -auto-approve \
        -var="create_arm_instance=true" \
        -var="arm_availability_domain=${ad}" >>"$LOG" 2>&1; then
      log "SUCCESS in ${ad} after ${attempt} attempts."
      exit 0
    fi

    log "Capacity unavailable in ${ad}."
  done
  log "All ADs exhausted. Sleeping ${SLEEP_SECONDS}s."
  sleep "$SLEEP_SECONDS"
done
