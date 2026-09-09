# Setup guide — build this lab from zero

This guide takes you from nothing to a running SOC/SIEM lab on Oracle Cloud's
free tier. No prior cloud experience assumed. Everything runs at zero cost.

The lab is built entirely from code: Terraform creates the cloud
infrastructure, Ansible configures the servers. You do not click things in a
console to build it — you run two commands.

---

## What you'll end up with

- 3 servers on Oracle Cloud (all free): a bastion, a vulnerable web target,
  and a SIEM host
- A deliberately hackable website (DVWA), unreachable from the internet
- Automated attacks running against it every 30 minutes
- A Wazuh SIEM detecting those attacks, mapped to MITRE ATT&CK
- A Grafana/Prometheus/Loki stack for infrastructure metrics and logs

---

## Part 1 — Oracle Cloud account

1. Go to **cloud.oracle.com** and start a free account.

2. **Choose your home region carefully — it is permanent.** Free-tier compute
   only exists in your home region and you cannot change it later without
   deleting the account. Pick a region with **3 availability domains** (more
   chances at scarce free ARM capacity): Ashburn, Phoenix, Frankfurt, or
   London. This lab was built in Frankfurt (`eu-frankfurt-1`).

3. **The card gotcha:** Oracle asks for a card to verify identity (it is not
   charged on the free tier). It does a small temporary authorization. If your
   card rejects international holds, this is where signup fails.

4. **Stay on the Free Tier. Never click "Upgrade to Pay As You Go"** — that
   attaches your card to real billing. The free tier cannot charge you.

5. Set a **$1 budget alarm** (Billing → Budgets) with alerts at 1% actual and
   100% forecast, so you're emailed the instant anything becomes chargeable.

---

## Part 2 — Your computer (the control machine)

You drive everything from your own machine. On Windows, use WSL (Ubuntu). On
Mac or Linux, use the terminal directly.

Install these tools:

```bash
# System basics
sudo apt update && sudo apt install -y unzip curl git python3-pip pipx tmux
pipx ensurepath

# Terraform (from HashiCorp's signed repo)
wget -O - https://apt.releases.hashicorp.com/gpg | \
  sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
  https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
  sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install -y terraform

# Ansible + the OCI SDK it needs, in an isolated environment
pipx install --include-deps ansible
pipx inject ansible oci

# OCI command-line tool
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"
```

Work inside the Linux home directory (`~`), never under `/mnt/c` — Windows
paths break SSH key permissions.

---

## Part 3 — Keys and credentials

**SSH key** (how you log into the servers):

```bash
ssh-keygen -t ed25519 -C "soc-lab" -f ~/.ssh/soc_lab_ed25519
```

**OCI API key** (how Terraform talks to Oracle):

```bash
mkdir -p ~/.oci && chmod 700 ~/.oci
openssl genrsa -out ~/.oci/oci_api_key.pem 2048
chmod 600 ~/.oci/oci_api_key.pem
openssl rsa -pubout -in ~/.oci/oci_api_key.pem -out ~/.oci/oci_api_key_public.pem
cat ~/.oci/oci_api_key_public.pem
```

In the OCI Console: profile icon → **My profile → API keys → Add API key →
Paste public key**. Paste the output above. Oracle then shows a config file
preview — copy it into `~/.oci/config`, and fix the `key_file=` line to point at
`/home/YOUR_USER/.oci/oci_api_key.pem` (absolute path). Then:

```bash
chmod 600 ~/.oci/config
oci iam region list --output table   # if this prints a table, auth works
```

---

## Part 4 — Get the code and configure it

```bash
git clone https://github.com/dininduabey/soc-lab.git
cd soc-lab/terraform
```

Copy the example variables file and fill in your values:

```bash
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

You need to set:
- `tenancy_ocid`, `user_ocid`, `fingerprint` — from your `~/.oci/config`
- `private_key_path` — `/home/YOUR_USER/.oci/oci_api_key.pem`
- `ssh_public_key` — paste the output of `cat ~/.ssh/soc_lab_ed25519.pub`
- `admin_cidr` — your public IP with `/32`: run `curl -s https://api.ipify.org`
- `region` — your home region
- availability-domain names — get them with:
  `oci iam availability-domain list --output table`

---

## Part 5 — Build it (two phases)

**Phase A: network + x86 hosts** (always available):

```bash
terraform init
terraform apply -var="create_arm_instance=false"
```

**Phase B: the ARM SIEM host.** Free ARM capacity is scarce and often
unavailable. A retry loop keeps trying across all availability domains until it
succeeds — this can take minutes or days:

```bash
tmux new -s arm
../scripts/arm-capacity-retry.sh
# Ctrl+B then D to detach; it keeps running.
# Watch progress: tail -f ../arm-retry.log
```

Once it reports SUCCESS, set `create_arm_instance = true` in
`terraform.tfvars` so the ARM host is protected from accidental destruction.

**Configure everything:**

```bash
cd ../ansible
ansible-playbook -i inventory/soclab.oci.yml site.yml
```

This hardens all hosts, installs Docker, deploys DVWA + nginx, the Grafana
stack, the attack tooling, the Wazuh SIEM, and the agents. On a slow link give
it 20–30 minutes. If the ARM host is brand new, cloud-init may still be
finishing — if it fails on soc-core, just re-run (it's idempotent).

---

## Part 6 — Access the dashboards

Everything is private and reached by SSH tunnel through the bastion. First add
the SSH config:

```bash
terraform -chdir=../terraform output -raw ssh_config_snippet >> ~/.ssh/config
chmod 600 ~/.ssh/config
```

**Wazuh SIEM:**
```bash
ssh -L 8443:<soc-core-private-ip>:443 soc-jump
# browse https://localhost:8443  (log in as admin)
```

**Grafana:**
```bash
ssh -L 3000:localhost:3000 soc-jump
# browse http://localhost:3000  (log in as admin)
```

**DVWA (the target):**
```bash
ssh -L 8080:<web-victim-private-ip>:80 soc-jump
# browse http://localhost:8080
```

Get the private IPs from `terraform -chdir=../terraform output`.

---

## Part 7 — See it work

Trigger an attack and watch it get detected:

```bash
ssh soc-jump "/opt/attack/run-attacks.sh <web-victim-private-ip>"
```

Wait ~2 minutes, then open the Wazuh dashboard (Last 24 hours) → Threat Hunting
and MITRE ATT&CK. You'll see the attacks classified by adversary technique.
Attacks also run automatically every 30 minutes.

---

## Known gotchas

- **Your home IP changes** (many ISPs rotate it): SSH will time out. Update
  `admin_cidr` in tfvars and run
  `terraform apply -target=oci_core_security_list.public`.
- **"Out of host capacity"** on the ARM instance is normal — the retry loop
  handles it. Best luck is off-peak hours in your region.
- **Never pass `-var="create_arm_instance=false"` once ARM is running** — it
  destroys the SIEM host.
- **The self-signed cert warning** on the dashboards is expected — it's the
  lab's own certificate authority.

---

## Tear down

To remove everything and stop all resource use:

```bash
cd terraform
terraform destroy
```

Then `terraform apply` rebuilds it from scratch. That reproducibility is the
whole point.
