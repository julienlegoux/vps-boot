---
type: Issue
title: "Add the caddy component with a UFW-aware check"
description: "Install Caddy from its official apt repo without opening any firewall port, and make the check report the UFW state for 80/443 rather than only the service state."
tags: [epic-1]
timestamp: 2026-08-17T11:00:00Z
epic: 1
issue: 07
slug: caddy-component
size: S
status: open
gh_issue: 25
depends_on: [1]
resource: https://github.com/julienlegoux/vps-boot/issues/25
---

# Add the caddy component with a UFW-aware check

## Summary

Caddy is the one new component that argues with the baseline. `apt install caddy`
starts and enables a systemd unit listening on `:80` — a port UFW denies, because
the baseline allows only the chosen SSH port. So `systemctl is-active` says
`active` on a server nobody can reach, and a check that looks only at the service
reports a healthy web server that serves nothing.

The component installs Caddy and **opens no firewall ports**. The closed firewall
is correct behaviour for an unattended box, not a defect; the check's job is to
make the state visible so the operator can decide.

## Scope

- Add an `install_caddy` / `check_caddy` / `register caddy …` triple in the
  Components section, `infra` group, registered before `herdr`.
  `COMPONENT_DEFAULT` 1, `COMPONENT_SCOPE` `system`, no sign-in hint.
- `install_caddy` uses the official apt repo (`dl.cloudsmith.io/public/caddy/stable`)
  with its keyring, following the pattern `install_docker` (`vps-boot.sh:450-466`)
  and `install_gh` (`:489-500`) already use for third-party apt repos — keyring
  into the same location convention, `apt update`, `apt install -y caddy`.
- **No `ufw allow` call anywhere in this component.** The firewall is the
  baseline's business.
- `check_caddy` reports two things: the service state, and the **UFW state for
  80/443**. When the service is running but the ports are denied, emit a `note`
  — not a `ko`. Per CONVENTIONS.md, `ko` is a real defect that fails the health
  check; a deliberately closed firewall is the recoverable, informed state `note`
  exists for. The note should say what to run to open them.
- The check must also print a real Caddy version string.
- Add a row to `README.md`'s toolchain table (`README.md:37-52`) noting that no
  ports are opened, and a row in `docs/planning/SPECS.md`'s third-party source
  table. The component roster and count at `SPECS.md:49-50` are reconciled
  once, in issue 09 — this PR does not touch that sentence.

## Out of scope

- **A wizard prompt offering to open 80/443.** It was the runner-up option and is
  worth revisiting while the wizard is already being touched — but it is not this
  issue and not this epic's wizard rework (issue 08) either. If it gets built, it
  gets its own issue.
- Any Caddyfile, site config, TLS setup, or reverse-proxy default. The component
  installs the binary and its service; configuration is the operator's.
- Changing `bl_ufw`'s deny-incoming default.
- Re-anchoring SPECS.md's line numbers past the moved blocks. The reorder
  shifts them, and every following issue shifts them again; the sweep is
  issue 09.

## Acceptance criteria / Definition of done

- [ ] `bash tests/test_vps_boot.sh` passes, registry-invariant case included.
- [ ] `bash -n vps-boot.sh` is clean.
- [ ] `grep -n 'ufw ' vps-boot.sh` shows no `ufw allow` inside `install_caddy`.
- [ ] On a fresh Ubuntu 24.04 host with `caddy` selected: `caddy version` prints
      a version, `systemctl is-active caddy` reports `active`, and
      `ufw status` shows **no** rule for 80 or 443.
- [ ] In that state, `vps-boot.sh check` prints the Caddy version as `✓` and a
      `!` note about 80/443 being closed — and the overall exit code is **0**, not
      1. A `ko` here would fail the health check on a correctly configured box;
      confirm the exit code explicitly.
- [ ] After manually running `ufw allow 80/tcp && ufw allow 443/tcp`, re-running
      `vps-boot.sh check` no longer emits the note.
- [ ] `README.md`'s toolchain row and `docs/planning/SPECS.md`'s third-party
      source table row updated in the same commit; the roster and count at
      `SPECS.md:49-50` are issue 09's.

## Relevant files / areas

- `vps-boot.sh:450-466` (`install_docker`) and `:489-500` (`install_gh`) — the
  third-party apt repo + keyring pattern.
- `vps-boot.sh:781-…` — `bl_ufw`, for what the baseline already allows.
- `vps-boot.sh:1424-1434` — the UFW block in `do_check`, for how UFW state is
  already parsed (`ufw status | grep -qE "^${SSH_PORT}/tcp[[:space:]]+ALLOW"`);
  reuse that shape.
- `vps-boot.sh:713-731` — the `herdr` block, which `caddy` registers before.
- `README.md:37-52` (toolchain table); `docs/planning/SPECS.md` (third-party
  source table — the roster and count at `SPECS.md:49-50` are issue 09's).
- `docs/planning/changes/change-1-expand-toolchain-components/18-caddy.md`.

## Dependencies

- **Blocked by**: issue 01.
- **Blocks**: nothing.

## PR size note

If this grows past ~1000, split it before opening the PR. Expect ~70.
