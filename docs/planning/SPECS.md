---
type: Technical Specification
title: "vps-boot — Technical Specs"
description: "Resumable Ubuntu 26.04 amd64 provisioning for autonomous agent VPSes."
tags: [planning, specs]
timestamp: 2026-09-05T15:00:00Z
status: final
---

# vps-boot — Technical Specs

## Target and distribution

One Bash script, version `0.1.0`, targeting fresh Ubuntu 26.04 amd64 systems
with systemd and OpenSSH already available. `main` is the stable published
installer and `develop` is integration. This release remains under validation;
see [release verification](/release-0.1.0.md).

`install [username] [port]` runs a TTY wizard. Root-only is the default;
a created sudo user is optional. `resume` takes no arguments and reuses the
recorded account, port and component selection. `harden [username]` completes
key enrollment and lockdown. `check [username] [port]` verifies recorded state.
`--version` reports the installer version. Extra arguments are rejected.

New installations reject SSH port 22, including zero-padded representations.
Ports are normalized as decimal integers. Legacy `check` and `harden` may
still read port 22; the verifier flags its listener as a policy failure.
There is no Ubuntu upgrade, unmanaged-host adoption or general update command.

## Registry and dependencies

The registry contains 23 default-on components in six display groups:

| Group | Components |
|---|---|
| core | sudo_nopasswd, tools, docker, gh |
| languages | node, python, go, java, rust |
| packaging | bun, pnpm, uv |
| agents | claude, opencode, codex, gemini, pi, hermes |
| cloud | vercel, neon, hostinger |
| infra | caddy, herdr |

`sudo_nopasswd` is excluded in root-only mode, leaving 22 components.
The register function retains its eight required arguments and optional sign-in
hint. `COMPONENT_DEPS` declares prerequisites: Python requires uv, npm tools
require Node. Resolution recursively adds and deduplicates prerequisites,
rejects unknown keys and cycles, and installs prerequisites before consumers.
Registry order determines display order and breaks dependency-order ties.
The confirmation screen shows the effective selection and firewall policy.

## Installation and state

The baseline comprises system update/base packages, unattended upgrades,
optional user, transactional firewall/SSH transition and fail2ban. Selected
components follow. Key enrollment and verification finish the run.

Under `/etc/vps-boot`:

| Path | Purpose |
|---|---|
| `lock` | Process-held flock for install, resume and harden |
| `components` | Effective ordered selection, written before installation |
| `config` | Account and active SSH port, committed after network setup |
| `journal/schema` | Resume format version (`1`) |
| `journal/intent` | Account, port, user mode and installer version; no password |
| `journal/<step>` | pending/running/succeeded/failed followed by verification output |
| `journal/network-backup` | Recovery copy for an interrupted network transition |
| `journal/apt-*.timer` | Saved timer activity during package operations |

Journal and selection writes use temporary files and atomic rename; journal
content is root-only. Successful steps are probed before being skipped. Failed,
running or unhealthy steps are executed again. Component probes record observed
versions; installer exit success alone does not establish completion.

A password is requested again only when created-user setup is unfinished and
is cleared as soon as that step completes. The user creation step tolerates an
account it created before interruption. A new install refuses existing state.
Legacy state without a journal supports check/harden but cannot be resumed.

APT timers are stopped while their active services are allowed to finish within
a bounded wait. Services are never killed to free a dpkg lock. Timer restoration
and lock-timeout cleanup run on success, failure and catchable termination.
SIGKILL/power loss leave recorded state for the next resume. The temporary APT
lock-timeout fragment preserves a pre-existing file. Security-only unattended
updates are configured after distro defaults, clearing inherited origin lists;
automatic reboot remains disabled.

## Runtime policy

Latest stable versions are resolved for work that must execute, including a
retry; already verified components are retained. There is no dependency lockfile.
Node uses NodeSource LTS. npm installers enforce package engine constraints.
Java probes installable LTS majors and rejects early-access candidates. Go uses
the official stable version plus its published SHA-256 before replacing the
previous installation. Hostinger also verifies release checksums.

uv installs CPython under `/opt/vps-boot/python`. A separate versioned development
venv is seeded with pip. `/usr/local/bin/python` is a wrapper executing that
venv's interpreter by its original path (an external symlink can lose venv
discovery). Neither `/usr/bin/python3` nor its PATH resolution is replaced.
The interpreter must report a final release. Project dependencies belong in
project venvs; the shared bootstrap environment is root-managed.

Rust toolchains and shims live under `/usr/local/rustup` and `/usr/local/cargo`.
Login profiles set RUSTUP_HOME to the shared toolchain, CARGO_HOME to each
user's `~/.cargo`, and add the shared shim directory to PATH. Toolchain updates
remain administrator-owned, while project builds and caches work as the user.

Hermes runs in the selected account's home. Its temporary sudoers allowance is
validated and removed by subshell EXIT/signal cleanup. Existing unmanaged
Hermes allowance files are not overwritten. Cloud and agent authentication is
left to the operator; installation does not provision account credentials.

## Network policy and verification

UFW denies incoming connections by default and permits the selected SSH port.
Caddy selection additionally permits 80/tcp and 443/tcp; UDP 443 is not opened.
Existing UFW rules are preserved. The transition temporarily allows old SSH
ports until the new sshd listener is confirmed. Recovery material is saved
before changing firewall/SSH and restored on a failed transition. A resumed
installation does not intentionally re-enable an already applied key-only policy.

The verifier checks actual sshd listeners, effective authentication policy,
service activity, socket masking, firewall rules, fail2ban and unattended
updates. Component version commands must succeed and return a parseable
version. Docker, Compose and buildx are checked separately. Closed Caddy ports
remain a warning because the operator may deliberately close them after setup.
Unknown persisted component keys produce a diagnostic and do not abort the
remaining checks.

Docker-published ports can bypass UFW rules. This installer does not introduce
a Docker forwarding policy; operators must bind private containers to loopback
or manage Docker's own filtering rules.

## Tests and CI

Woodpecker's `.woodpecker/test.yaml` runs on push, PR, manual and tag events in
Ubuntu 26.04. It executes Bash syntax, ShellCheck and the test harness as root
with an actual OpenSSH validator. `.gitattributes` enforces LF for shell/YAML.

`tests/Dockerfile` supplies the same Linux prerequisites locally.
`tests/smoke_user.sh` compiles and runs minimal projects as an unprivileged
account. `tests/smoke_system.sh` exercises the live baseline, nested Docker,
Caddy, key-only SSH and failure/resume in a disposable privileged systemd
container. That privileged scenario is separate from ordinary PR CI and is
not assumed validated until its execution is recorded.

Docker validation does not cover physical/virtual machine boot, cloud-init or
provider firewall behavior. Test evidence and outstanding limits belong in
[release verification](/release-0.1.0.md).
