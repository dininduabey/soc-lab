# Runbook

## Prerequisites

- OCI Always Free tenancy, home region `eu-frankfurt-1`
- `~/.oci/config` with an API signing key
- `terraform`, `ansible`, `oci` CLI installed
- SSH keypair at `~/.ssh/soc_lab_ed25519`
- `terraform/terraform.tfvars` populated (see `terraform.tfvars.example`)

## Build from nothing

```bash
# 1. Provision the x86 tier (always available)
cd terraform
terraform init
terraform apply -var="create_arm_instance=false"

# 2. Obtain the ARM host (capacity-gated; runs until it succeeds)
../scripts/arm-capacity-retry.sh

# 3. Configure every host
cd ../ansible
ansible-playbook -i inventory/soclab.oci.yml site.yml
```

## Access

```bash
# Append the generated SSH config once
terraform -chdir=terraform output -raw ssh_config_snippet >> ~/.ssh/config

# Bastion
ssh soc-jump

# DVWA via tunnel through the bastion
ssh -L 8080:<web-victim-private-ip>:80 soc-jump
# then browse http://localhost:8080
```

## Common operations

| Task | Command |
|------|---------|
| Re-apply configuration | `ansible-playbook -i inventory/soclab.oci.yml site.yml` |
| Check what would change | add `--check --diff` |
| Target one tier | append `--limit role_victim` |
| Verify SSH hardening | `ansible ... -m shell -a "sshd -T \| grep -i passwordauth" -b` |
| View nginx access log | `ansible role_victim -m shell -a "tail /var/log/nginx/dvwa_access.log" -b` |

## Teardown and rebuild

```bash
cd terraform
terraform destroy          # removes everything
terraform apply -var="create_arm_instance=false"   # rebuild x86 tier
```

State lives in `terraform.tfstate` (gitignored). The lab is fully reproducible
from code — no manual console steps.

## Admin IP rotated (locked out of SSH)

If SSH to the bastion times out after your ISP changes your public IP:

```bash
cd terraform
sed -i "s|admin_cidr .*|admin_cidr       = \"$(curl -s https://api.ipify.org)/32\"|" terraform.tfvars
terraform apply -target=oci_core_security_list.public
```

The `/32` restriction is deliberate — the bastion accepts SSH from one address
only. A rotated IP locking you out is the control working as intended.

## Access Grafana

Grafana binds to localhost on the jumpbox only. Reach it by tunnel:

```bash
ssh -L 3000:localhost:3000 soc-jump
# browse http://localhost:3000  (user: admin)
```

## Vault

The Grafana password is Ansible-Vault encrypted. The vault key must exist at
`~/.soc-lab-vault-pass` (referenced by `ansible.cfg`) for playbook runs to
decrypt it. This file is never committed.

## Trigger an attack manually

```bash
ssh soc-jump "/opt/attack/run-attacks.sh <web-victim-private-ip>"
```

Attacks also run automatically every 30 minutes via cron on the jumpbox.

## Running a live attack + monitoring demo

Watch the lab attack itself and see it land on the dashboard.

**1. Open the Grafana tunnel** (leave this terminal open):

```bash
ssh -L 3000:localhost:3000 soc-jump
```

Browse to http://localhost:3000, log in as `admin`, then
Dashboards -> SOC Lab -> SOC Lab Overview.

**2. Trigger an attack** (in a second terminal):

```bash
ssh soc-jump "/opt/attack/run-attacks.sh <web-victim-private-ip>"
```

**3. View it.** Set the dashboard time range to "Last 30 minutes" and
refresh (or set auto-refresh to 10s). Watch:
- nginx request rate spike
- victim CPU rise
- the attack log stream fill with highlighted Nikto / script / injection lines

The metric panels update first (Prometheus scrapes every 30s); the log panel
follows a few seconds later (Loki ingestion). Widen the window and refresh if
a panel shows "No data".

Note: attacks also run automatically every 30 minutes via cron, so the
dashboard shows periodic activity with no manual trigger.

## Access the Wazuh SIEM

The Wazuh dashboard binds to soc-core's private interface on port 443. Reach it
by tunnel through the bastion:

```bash
ssh -L 8443:<soc-core-private-ip>:443 soc-jump
# browse https://localhost:8443  (accept the self-signed cert — it's the lab's own CA)
# log in as admin
```

Set the dashboard time range to "Last 24 hours" and open Threat Hunting or
MITRE ATT&CK to see classified alerts.

## Check the SIEM pipeline is healthy

Run these against the SIEM host (`role_siem`) if the dashboard shows no data:

```bash
# 1. Is the manager generating alerts?
wc -l /var/ossec/logs/alerts/alerts.json

# 2. Did they reach the indexer? (want a wazuh-alerts-4.x-* index with docs)
curl -s -k -u admin:<password> 'https://<soc-core-ip>:9200/_cat/indices/wazuh-alerts-*?v'

# 3. Are agents connected? (run on soc-core)
/var/ossec/bin/agent_control -l

# 4. If alerts exist on disk but not in the indexer, check Filebeat delivery
#    (connectivity vs. actual shipping are different — run it in the foreground):
systemctl stop filebeat
timeout 12 filebeat -e -c /etc/filebeat/filebeat.yml 2>&1 | grep -iE 'error|established'
systemctl start filebeat
```

A `_type` error in step 4 means the indexer's
`compatibility.override_main_response_version` flag is missing — see
security-decisions.md.

## Enroll a new agent

Any host in the `role_victim` or `role_bastion` groups gets a Wazuh agent
automatically via the `wazuh_agent` role. To add a new monitored host, tag its
instance appropriately in Terraform and re-run:

```bash
ansible-playbook -i inventory/soclab.oci.yml site.yml --limit <new-host-group>
```

The agent finds the manager via the `role_siem` group in dynamic inventory — no
manual key exchange.

## Generate attacks and watch them classified

```bash
ssh soc-jump "/opt/attack/run-attacks.sh <web-victim-private-ip>"
```

Wait ~2 minutes for ingestion, then refresh the Wazuh dashboard. Host-layer
signals (brute-force, scans) appear in Wazuh; web-layer payloads (SQLi, XSS)
appear in the Grafana/Loki attack panel. Attacks also run automatically every
30 minutes via cron on the jumpbox.

## Session lifecycle — boot, attack, close

### Boot (start a session)

If the instances were only *stopped* (not destroyed), bring them back:

```bash
cd terraform && terraform apply   # starts/reconciles; keeps create_arm_instance=true
cd ../ansible && ansible-playbook -i inventory/soclab.oci.yml site.yml   # optional: ensures config
```

If your home IP changed since last time, SSH will time out — update `admin_cidr`
in `terraform/terraform.tfvars` and run
`terraform apply -target=oci_core_security_list.public` first.

### Attack and observe

```bash
ssh soc-jump "/opt/attack/run-attacks.sh <web-victim-private-ip>"
```

Then tunnel to the Wazuh dashboard (`ssh -L 8443:<soc-core-ip>:443 soc-jump`,
browse https://localhost:8443) and watch under Threat Hunting / MITRE ATT&CK.
Attacks also run automatically every 30 minutes via cron.

### Close (end a session)

Nothing to clean up manually — disk retention is automatic:
- A daily cron (`/usr/local/bin/wazuh-retention.sh`, 03:30) deletes alert
  indices and raw logs older than 3 days, via the OpenSearch API.
- Docker log rotation and manager archive logging are capped.

You may leave the lab running (no cost on the free tier). To fully idle it you
*can* stop the instances, but stopping the ARM host risks not regaining scarce
free ARM capacity on restart — leaving it running is safer.

### Disk check (if you ever suspect a full disk)

```bash
# free space on the SIEM host
ansible -i inventory/soclab.oci.yml role_siem -b -m shell -a "df -h /"

# force a retention run now
ansible -i inventory/soclab.oci.yml role_siem -b -m shell -a "/usr/local/bin/wazuh-retention.sh"
```

### Full teardown / rebuild

```bash
cd terraform && terraform destroy      # removes everything
# later: terraform apply + arm-capacity-retry.sh + ansible-playbook to rebuild
```
