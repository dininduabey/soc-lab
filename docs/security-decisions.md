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

## The `create_arm_instance` footgun

The ARM host is toggled by a Terraform variable so the x86 tier can be built
while ARM capacity is unavailable. Once ARM was obtained, running
`terraform apply -var="create_arm_instance=false"` — correct earlier, when no
ARM instance existed — destroyed the provisioned SIEM host. The fix was to set
`create_arm_instance = true` in tfvars so a plain apply protects it, and to
document that the false flag must never be passed once ARM is live. Lesson: a
toggle that is safe in one phase becomes a demolition order in the next; pin
its value once the thing it guards exists.

## Wazuh runs natively on ARM, not in Docker

Wazuh's indexer Docker image is amd64-only and would run emulated on the Ampere
host — high memory use and OOM kills. The native apt packages support aarch64,
so Wazuh (indexer, manager, dashboard) is installed component-by-component from
the Wazuh repository rather than via containers. DVWA and the Grafana stack
remain containerized, where multi-arch images exist. The choice per component
is "container where the image is clean multi-arch; native where it isn't."

## Indexer JVM heap tuning

The Wazuh indexer is a JVM application; its heap defaults can be wrong for a
constrained host. On the 12 GB ARM box the heap is pinned to 4 GB via a
`jvm.options.d/` drop-in (not by editing the main options file, which upgrades
overwrite), leaving room for the manager, the Node.js dashboard, Filebeat, and
the OS. `-Xms` and `-Xmx` are set equal to avoid heap-resize pauses.

## Filebeat 7.10.2 vs OpenSearch 2.x — the `_type` incompatibility

The single hardest bug in the project. Symptom: the Wazuh dashboard showed zero
alerts while the manager's alert log held thousands. Traced through five layers:
the manager WAS detecting (8,000+ MITRE-mapped alerts on disk); the indexer had
no `wazuh-alerts-*` index; Filebeat connected fine (`filebeat test output` OK)
but shipped nothing; running Filebeat in the foreground revealed the real error:

    400 Bad Request: Action/metadata line [1] contains an unknown parameter [_type]

Wazuh 4.14 pins Filebeat 7.10.2, which still sends the deprecated `_type` field
in bulk requests. OpenSearch 2.x (the indexer) removed `_type` and rejects it.
The fix is not to upgrade Filebeat (that breaks the Wazuh integration) but to
set `compatibility.override_main_response_version: true` in the indexer config,
which makes the indexer report as ES 7.x to older clients so Filebeat sends an
accepted format. Baked into the indexer role for reproducibility.

Lesson: `filebeat test output` proves connectivity, not delivery. When a
pipeline "connects but ships nothing," run the shipper in the foreground to get
the real per-document error — the empty log file was hiding a rejection that
only surfaced on stderr.

## Wazuh agents report host events, not web logs

The agents on the victim and jumpbox monitor system logs (auth, syslog), file
integrity, and process events by default — not the nginx access log. The
web-layer attacks (SQLi, XSS, scanner floods) land in nginx logs and are
surfaced by the Grafana/Loki stack; the host-layer signals (brute-force auth,
sudo, scans) are what Wazuh's default rules classify. The two stacks see
different, complementary slices of the same attack.
