---
type: Release Verification
title: "vps-boot 0.1.0 — verification and release gate"
description: "Observed Ubuntu 26.04 tool versions, Docker test evidence and outstanding service validation."
tags: [release, testing, ubuntu]
timestamp: 2026-09-05T15:00:00Z
status: draft
---

# vps-boot 0.1.0

## Changes

This release retains the complete agent-oriented catalogue. It adds resumable
installation, explicit component dependencies, stable Python through uv,
strict version probes, download staging for Go, temporary privilege cleanup,
bounded APT service waits and Woodpecker CI. New installations target Ubuntu
26.04 amd64 only. SSH port 22 is rejected; Caddy opens 80/tcp and 443/tcp.

No additional optional tools were selected. `psmisc` is a bootstrap dependency
for lock inspection. No credentials were provisioned for any agent or cloud CLI.

## Branch comparison

Remote heads were verified on 2026-09-05: main `86cf109`, develop `be2f0ba`.
The feature branch starts from develop and retains its rerunnable `harden`
command and timer-restoration-before-verification fix. The local main checkout
was stale and was not used as the release baseline. The commits unique to the
remote main history were merge commits, not additional missing features.

## Observed installations

The following were installed from the actual upstream sources inside an
ordinary disposable Ubuntu 26.04 Docker container on 2026-09-05. These are
observations, not pins or promises about future installations.

| Tool | Observed version |
|---|---|
| uv | 0.12.10 |
| Python / pip | 3.14.7 / 26.2.1 |
| Node / Bun / pnpm | 24.20.0 / 1.4.2 / 11.25.0 |
| Go | 1.27.1 |
| Java / javac | 25.0.4 / 25.0.4 |
| Rust / Cargo | 1.98.1 / 1.98.1 |
| jq / ripgrep / fd | 1.8.1 / 15.1.0 / 10.3.0 |
| htop / tree | 3.4.1 / 2.3.1 |
| GitHub CLI | 2.100.0 |
| Claude Code | 2.1.261 |
| opencode | 1.18.29 |
| Codex | 0.153.4 |
| Gemini CLI | 0.58.0 |
| pi | 0.85.1 |
| Hermes, root and created-user installations | 0.21.0 |
| Vercel | 59.11.7 |
| Neon CLI | 4.14.1 |
| Hostinger | 3.32.0 |
| herdr | 0.8.2 |
| Docker / Compose / buildx | 29.8.0 / 5.5.1 / 0.37.0 |
| Caddy | 2.11.4 |

Docker and Caddy packages and version commands were checked without starting
a nested Docker daemon or changing the container firewall. UFW calls in the
Caddy package test were explicitly stubbed. This does not validate network
exposure, service startup or restart behavior.

## Executed checks

- **146 tests passed, 0 failed** inside Ubuntu 26.04. The suite runs as root with real OpenSSH
  configuration validation and stubbed mutations for unit scenarios.
- ShellCheck errors and Bash syntax are checked for the script and test files.
- Woodpecker CLI lint accepts `.woodpecker/test.yaml`; the remote repository
  is enabled and the CLI account is authenticated.
- A created non-root account successfully creates a Python venv, uses pip,
  compiles/runs Rust, Go and Java, builds a Cargo project and runs Node plus
  agent/cloud version commands (`tests/smoke_user.sh`).
- Hermes was installed as root and as a created user without an interactive setup prompt; the temporary sudoers rule was removed.

Live installation exposed and corrected three defects beyond static checks:
uv's externally managed interpreter needs a separate pip environment; an
external symlink can lose Python venv discovery; a generic `--version` probe
is incorrect for Hostinger, which requires `version`. The script's release
constant is named `VPS_BOOT_VERSION` to avoid colliding with os-release.

## Pending release gate

The privileged systemd/UFW/nested-Docker scenario has not been executed.
Automatic approval review rejected `docker run --privileged` because the
general Docker authorization did not explicitly cover elevated container
capabilities. User approval was requested; no privileged container was started.

`tests/smoke_system.sh root` and `tests/smoke_system.sh user` are prepared to
exercise a real baseline, an injected Caddy failure, resume, SSH reconnect,
Docker hello-world and service restarts in disposable systemd containers.
The scripts must not run on an existing VPS or the workstation itself.

Do not tag or merge this release into main before the service acceptance gate
is completed or the user explicitly changes that gate. Docker tests cannot
establish VPS boot, cloud-init or provider-firewall compatibility even when green.

Remote CI has not run: automatic approval review rejected publication of the
feature branch to the public GitHub repository. Woodpecker configuration lint
and the equivalent local Linux checks passed. No remote branch, tag or release
was published.
