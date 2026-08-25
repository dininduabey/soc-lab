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
