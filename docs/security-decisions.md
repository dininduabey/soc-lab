# Security decisions

A log of non-obvious choices and the reasoning behind them. These are the
decisions that distinguish a deliberately-built lab from a copied tutorial.

## The vulnerable app is never internet-facing

DVWA is intentionally exploitable. A public IP on it would be found by mass
scanners within the hour and repurposed for abuse — which on a free tier gets
the tenancy terminated. Attack traffic therefore originates from inside the
VCN (the bastion), never the public internet. Three independent controls
enforce the isolation (see architecture.md).

## Docker bypasses the host firewall

Discovered during setup: the DVWA container's published port was reachable
from the bastion while nginx on the same host was blocked. Cause — Docker's
published ports are DNAT'd through the iptables FORWARD chain and never
traverse INPUT, so a host firewall that looks correct provides no protection
over a container's published port. Implication: container port bindings and
the cloud security list are the real controls, not host iptables. Containers
are bound to the private interface explicitly rather than 0.0.0.0.

## iptables rule ordering is computed, not hardcoded

Oracle's Ubuntu image ends the INPUT chain with a REJECT catch-all. A new
ACCEPT rule must be inserted above it. Because Docker also inserts rules and
the chain differs per host, the playbook finds the REJECT rule's position at
runtime and inserts relative to it, rather than assuming a fixed line number.

## SSH config precedence

Ubuntu 24.04 assembles sshd config from drop-ins and uses the first value it
finds per keyword. Oracle's image ships a cloud-init drop-in enabling password
auth. Hardening is therefore delivered as a drop-in named to sort *before* it
(`01-`), and validated with `sshd -t` on the full assembled config before any
restart — so a bad edit fails the play rather than locking out the host.

## Least privilege, applied concretely

- Bastion SSH restricted to a single administrator /32, not 0.0.0.0/0.
- GitHub token scoped to the minimum; the `workflow` scope requirement caught
  a workflow push and had to be granted explicitly — the restriction working
  as intended.
- ed25519 keys, one per service, never reused across OCI and GitHub.
- CI runs with `permissions: contents: read`.

## Free-tier constraints as design inputs

- ARM Always Free is a contended leftover pool; capacity is obtained via an
  AD-rotating retry loop rather than a manual console click.
- Instance shapes and volume sizes are pinned to stay inside Always Free
  limits permanently, so trial expiry is a non-event.
- Wazuh runs from native packages, not Docker — the indexer image is amd64-only
  and would run emulated (and OOM) on the ARM host.

## Metrics pull vs. log push — a firewall asymmetry

Prometheus metrics worked immediately but Loki log ingestion failed silently.
Cause: Prometheus *pulls* (jumpbox initiates to victim, allowed intra-VCN),
while Promtail *pushes* (victim initiates to jumpbox on :3100). The jumpbox's
security list was written for a pure bastion — SSH inbound only — so it
rejected the inbound Loki connection at the cloud firewall, before the host
was ever reached. Fix: one explicit ingress rule for :3100 from the VCN CIDR,
added in Terraform. Adding a receiving service to a bastion changes what
"bastion" means for its firewall.

## Grafana admin password only applies on first init

`GF_SECURITY_ADMIN_PASSWORD` is honoured only when Grafana first creates the
admin user. On an existing data volume it is ignored on restart. The vaulted
password therefore applies correctly on a clean `terraform destroy` + rebuild
(empty volume, user created fresh), but changing it on a live instance needs
`grafana cli admin reset-admin-password`. The IaC is correct for fresh deploy;
the CLI reset was a one-time migration, not a permanent workaround.

## Secrets management

The Grafana admin password is encrypted with Ansible Vault (`encrypt_string`
in group_vars). No plaintext secret exists in the repository. The vault key
lives outside the repo in the operator's home directory and is gitignored.
