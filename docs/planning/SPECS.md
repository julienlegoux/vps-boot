---
type: Technical Specification
title: "vps-boot — Technical Specs"
description: "A single-file Bash installer that hardens a fresh Ubuntu LTS VPS and installs a selectable dev toolchain, driven by an interactive TTY wizard."
tags: [planning, specs]
timestamp: 2026-08-16T07:28:00Z
status: final
mapped_commit: 2e2cb762a6c0e97fb8613ed4b4a331695b2fcd1d
mapped_at: 2026-08-16T07:28:00Z
---

# vps-boot — Technical Specs

## Stack

Bash, targeting Ubuntu LTS. There is no package manifest, no dependency lockfile,
and no build step — the deliverable is one executable script.

| Element | Value |
|---|---|
| Language | Bash (`#!/usr/bin/env bash`, `set -euo pipefail`) |
| Minimum shell | Bash 4+ — the script relies on `declare -A` associative arrays (`vps-boot.sh:385-391`), `mapfile`, `BASH_REMATCH`, and `${var,,}` case conversion |
| Source | `vps-boot.sh`, 1539 lines, single file |
| Tests | `tests/test_vps_boot.sh`, 662 lines, hand-rolled harness |
| Target OS | Ubuntu LTS (apt + systemd assumed throughout) |
| Versioning | No git tags. `v0.0.1` / `v0.0.2` / `v0.0.3` exist only as merge-commit subjects |

Runtime dependencies are the target host's system tooling, not vendored libraries:
`apt`/`dpkg`, `systemd` (`systemctl`, `journalctl`), `ufw`, `fail2ban`,
`openssh-server` (`sshd`, `ssh-keygen`), `iproute2` (`ss`), `sudo`/`visudo`,
`curl`, `awk`, `grep`, `sed`, `od`, `getent`, `tput`. `bl_update`
(`vps-boot.sh:766-772`) installs the subset that is not guaranteed present.

## Architecture

A single script read top to bottom, in ten ordered sections: header and shell
options, constants, UI library, component registry, components, baseline, SSH key
enrollment, validation helpers, flows, entry point.

**Component registry.** The toolchain is data, not control flow. `register()`
(`vps-boot.sh:396-407`) appends a key to the `COMPONENTS` array and populates
seven parallel associative arrays keyed by that id: `COMPONENT_NAME`,
`COMPONENT_DESC`, `COMPONENT_DEFAULT`, `COMPONENT_SCOPE`, `COMPONENT_INSTALL`,
`COMPONENT_CHECK`, `COMPONENT_SIGNIN`. Adding a tool means writing `install_<key>`,
`check_<key>`, and one `register` line — the wizard's multi-select, QuickStart's
defaults, the run loop, and the verifier all iterate the registry, so no other
plumbing changes. Registration order is run order.

Twelve components are registered, in run order: `sudo_nopasswd`, `docker`, `gh`,
`node`, `bun`, `pnpm`, `claude`, `opencode`, `python`, `go`, `hermes`, `herdr`.
All default to on. `COMPONENT_SCOPE` is `system` for every component except
`hermes`, which is `user` and runs its installer through
`sudo -u "$USERNAME" -H bash`.

**Baseline.** Five functions — `bl_update`, `bl_user`, `bl_ufw`, `bl_ssh_harden`,
`bl_fail2ban` — are mandatory, deliberately *not* registered, and invoked in a
hardcoded order by `cmd_install` (`vps-boot.sh:1269-1275`). `bl_user` is the one
conditional step, skipped in root-only mode.

**Flows.** `main` dispatches to `cmd_install`, `cmd_check`, or `cmd_help`.
`cmd_install` is wizard → confirm → run → `enroll_ssh_key` → `do_check`.
`cmd_check` reconstructs the component list from persisted state, then calls the
same `do_check`, so the inline and standalone verifier are one code path.

**Sourcing guard.** `vps-boot.sh:1537-1539` runs `main` only when the file is
executed rather than sourced, and the guard also treats an empty `BASH_SOURCE[0]`
as executed so `curl … | bash -s install` still works. This is what lets the test
harness `source` the script and call individual functions.

**Two user modes.** `configure_user_mode` (`:1095-1109`) sets `USERNAME=root` and
`CREATE_USER=0` for the default root-only path, or `CREATE_USER=1` for a created
sudo user. Mode is threaded through the rest of the script by branching on
`$USERNAME == "root"`: `component_is_applicable` filters `sudo_nopasswd` out of
root installs, `add_docker_group_if_needed` skips the group add, `bl_ssh_harden`
picks `PermitRootLogin yes` vs `no`, and several `check_*` functions branch on it.

## Data model & storage

No database. State is files on the target host, all of them env-overridable so the
test harness can redirect them into a temp directory (`vps-boot.sh:16-25`).

| Path | Constant | Purpose |
|---|---|---|
| `/etc/vps-boot/components` | `STATE_FILE` | Enabled component keys, one per line. Written at the end of the run phase; read by standalone `check` |
| `/tmp/vps-boot.log` | `LOG_FILE` | Per-step stdout+stderr, truncated at install start |
| `/etc/ssh/sshd_config.d/00-vps-boot.conf` | `SSHD_DROPIN` | The managed sshd settings — `Port`, `PermitRootLogin`, `PasswordAuthentication`, `KbdInteractiveAuthentication` |
| `/etc/ssh/sshd_config.bak.<epoch>` | — | Timestamped backup taken once by `bl_ssh_harden` |
| `/etc/sudoers.d/90-vps-boot-<user>` | `SUDOERS_DIR` | NOPASSWD rule from the `sudo_nopasswd` component |
| `/etc/apt/apt.conf.d/99-vps-boot-lock-timeout` | `APT_LOCK_CONFIG` | `DPkg::Lock::Timeout "180"`. Transient — armed by an `EXIT` trap and removed when the run ends |

`/etc/sudoers.d/99-vps-boot-hermes` is a second, temporary sudoers rule written by
`install_hermes` and removed by a `RETURN` trap. It hardcodes its path
(`vps-boot.sh:687`, `:690`) rather than using `$SUDOERS_DIR`, so unlike every other
state path it is not redirectable under test.

The state file is the only thing that survives to inform a later `check`. When it
is absent, `cmd_check` falls back to checking every registered component.

## Auth

There is no application auth. The subject is the host's SSH access policy.

**During install**, `bl_ssh_harden` moves sshd to the chosen port and leaves
password authentication *on*, so the operator can still get in to push a key. Root
login is `yes` in root-only mode and `no` when a user was created.

**Lockdown** is a separate, opt-in step. `enroll_ssh_key` (`:1044-1089`) prints
copy-pasteable `ssh-copy-id` commands, then offers `ok` / `skip`. Choosing `ok`
does not by itself lock down — `authorized_keys` must be non-empty *and*
`ssh-keygen -l` must parse it as a real key. Only then does `lockdown_ssh` set
`PasswordAuthentication no`, `KbdInteractiveAuthentication no`, and
`PermitRootLogin prohibit-password` for root-only installs. A missing or malformed
key leaves password auth on and warns.

**Policy is verified against effective config, not the file.** `apply_sshd_policy`
(`:946-979`) writes the drop-in, then `validate_sshd_policy` runs `sshd -t` and
parses `sshd -T -C user=…,host=…,addr=…` output. That means a `Match` block
elsewhere in `sshd_config` cannot silently override the managed values. The policy
is checked twice when a user was created — once in the user's context and once in
root's (`:904-908`) — because `PermitRootLogin` only shows its true value in root's
context. It also asserts exactly one effective `Port`, and that at least one
effective `ListenAddress` is non-loopback (`validate_sshd_listeners`, `:849-889`),
so a loopback-only bind cannot pass as success.

`sshd_root_is_key_only` accepts both `prohibit-password` and the legacy
`without-password` spelling.

Adjacent controls: UFW defaults to deny-incoming and allows only the chosen
`<port>/tcp`; fail2ban runs an `sshd` jail on that port with a 1h ban after 5
retries in 10 minutes, `backend = systemd`.

## Interfaces & integrations

**CLI** — `install [username] [port]`, `check [username] [port]`, `--help`. Both
`install` and `check` require `EUID -eq 0`. `check` defaults to `root` and port
`1986`.

**Interactive TTY.** The wizard is the primary interface: `prompt_text`,
`prompt_password`, `prompt_radio`, `prompt_multiselect`. Every read is redirected
`< /dev/tty`, which is what makes the documented `curl … | sudo bash -s install`
distribution path work — stdin is the script itself. Prompts return values by
writing to a caller-named variable rather than to stdout, because the UI rendering
goes to stdout and command substitution would capture it.

**Distribution** — `curl -fsSL https://raw.githubusercontent.com/julienlegoux/vps-boot/{main,develop}/vps-boot.sh | sudo bash -s install`.

**Third-party sources**, all fetched over HTTPS at install time:

| Component | Source |
|---|---|
| `docker` | `download.docker.com` apt repo, keyring in `/etc/apt/keyrings/docker.asc` |
| `gh` | `cli.github.com` apt repo, keyring in `/usr/share/keyrings/` |
| `node` | NodeSource `setup_lts.x` script, piped to `bash` |
| `bun`, `pnpm`, `claude`, `opencode` | npm registry, global installs (`bun`, `pnpm`, `@anthropic-ai/claude-code`, `opencode-ai`) |
| `python` | `ppa:deadsnakes/ppa` |
| `go` | `go.dev/VERSION?m=text` then the matching tarball into `/usr/local` |
| `hermes` | NousResearch `install.sh` from GitHub raw, piped to `bash` |
| `herdr` | `herdr.dev/install.sh`, piped to `sh` with `HERDR_INSTALL_DIR=/usr/local/bin` |

`bun`, `pnpm`, `claude` and `opencode` are registered `system` scope but install
through `npm -g`, so all four have a hard ordering dependency on `node` appearing
earlier in the registry.

`herdr` is the only component that pins its upstream installer's target directory.
Its default is `$HOME/.local/bin`, which is not on `PATH` for a fresh root-only
box, so `HERDR_INSTALL_DIR=/usr/local/bin` makes the binary resolve for root and any
created user alike.

`install_python` does not repoint `/usr/bin/python3`, deliberately: distro services
such as fail2ban are built against the system interpreter. It probes deadsnakes
with `apt install --dry-run` to find the newest version that actually has an
installable candidate, then exposes it only as `python` via `update-alternatives`.

## Deployment & operations

**No CI.** There is no `.github/` directory, no workflow, and no pre-commit
configuration. Nothing runs `tests/test_vps_boot.sh` automatically.

**No release process.** No tags, no changelog, no version constant in the script.
`main` and `develop` are both live install targets documented in the README, so
merging to either publishes immediately to anyone using that curl URL.

**Failure handling.** `step_run` runs each step in a subshell that re-arms
`set -euo pipefail`, captures the exit code, and on failure prints `✗` and the last
15 lines of the log. The script stops at the first failed step. Re-running install
on an already-provisioned host is explicitly not supported — `bl_user` fails at
`useradd`.

**Recovery** is manual and documented in the README: restore the timestamped
`sshd_config` backup, remove or fix the drop-in, `sshd -t`, reload `ssh.service`.

**Observability** is the log file plus the verifier. `do_check` counts
`PASS`/`FAIL`/`WARN` via the `ok`/`ko`/`note` helpers and exits 1 if anything
failed, which makes `check` usable as a health probe.

**Known operational hazards handled explicitly in code**: socket-activated SSH
(`ssh.socket` is disabled and masked so it cannot rebind `:22`), orphan sshd
listeners left by `KillMode=process` (pkilled by pattern), a listener that does not
actually bind after `systemctl start` (polled up to 5×1s), background apt locks
during unattended-upgrades (`DPkg::Lock::Timeout` 180s), and a missing `/run/sshd`
blocking `sshd -t` on hosts where `ssh.service` never started.

## Testing infrastructure

One harness, `tests/test_vps_boot.sh`, run manually:

```bash
bash tests/test_vps_boot.sh              # all
bash tests/test_vps_boot.sh <filter>     # or TEST_FILTER=<substring>
```

32 cases, registered as explicit `run_test "<label>" <fn>` lines at the bottom of
the file. Output is TAP-flavoured (`ok - <label>` / `not ok - <label>`), with a
`N passed, M failed` summary and a non-zero exit when anything failed.

The harness exercises the real script rather than a copy: it exports every
`VPS_BOOT_*` path constant into a `mktemp -d` sandbox, writes a fake
`sshd_config` with an `Include` line, then `source`s `vps-boot.sh` and calls
functions directly. Mocking is done by redefining shell functions and commands
(`chmod() { return 23; }`, stubbed `step_run`, stubbed `bl_*`) inside the subshell
`run_test` spawns, so overrides do not leak between cases.

Coverage is concentrated where the risk is: roughly half the cases are SSH policy —
`Match`-block overrides, unexpected listener ports, loopback-only listeners, extra
ports, reload failure, and drop-in restore on every failure path. The rest cover
the sourcing guard, `step_run` fail-fast, APT fragment lifecycle, both install
flows end to end, sudoers validation, and one case asserting the README documents
current behaviour.

Not covered: the UI/prompt library, the network-dependent `install_*` bodies, and
anything requiring a real Ubuntu host.

## Cross-cutting concerns

**Transactional file writes.** Every managed file is written the same way: `mktemp`
a candidate beside the target, write, `chmod`, validate, then `mv -f` into place —
and `rm -f` the candidate on any failure. `install_sudo_nopasswd` validates with
`visudo -cf` before the move, so an invalid rule can never replace a working one.
`apply_sshd_policy` goes further and keeps a backup of the previous drop-in,
restoring it if either validation or the service reload fails; if the reload failed
it also attempts to reload the restored config, so the box is never left on a
config that was never loaded.

**Fail-fast discipline.** `set -euo pipefail` at the top; `step_run`'s subshell
re-arms it because a function called from a conditional context would otherwise run
with `errexit` suppressed.

**Trap-scoped cleanup.** The APT lock fragment is armed with an `EXIT` trap
*before* it is written (`vps-boot.sh:1259-1260`), so an abort between the two
cannot strand it. `install_hermes` uses a `RETURN` trap for its temporary sudoers
rule.

**Secret handling.** `USER_PASSWORD` lives in a shell variable, is passed to
`chpasswd` over a pipe rather than the command line, and is cleared immediately
after the run phase (`vps-boot.sh:1283`).

**Presentation.** All user-visible output goes through the UI helpers; ANSI colors
are set to empty strings when stdout is not a TTY (`:28-40`).
