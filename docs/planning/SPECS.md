---
type: Technical Specification
title: "vps-boot — Technical Specs"
description: "A single-file Bash installer that hardens a fresh Ubuntu LTS VPS and installs a selectable dev toolchain, driven by an interactive TTY wizard."
tags: [planning, specs]
timestamp: 2026-08-17T01:55:00Z
status: final
mapped_commit: 34bb863a87144d382e92f1604e8fc4b4f143e416
mapped_at: 2026-08-17T01:55:00Z
---

# vps-boot — Technical Specs

## Stack

Bash, targeting Ubuntu LTS. There is no package manifest, no dependency lockfile,
and no build step — the deliverable is one executable script.

| Element | Value |
|---|---|
| Language | Bash (`#!/usr/bin/env bash`, `set -euo pipefail`) |
| Minimum shell | Bash 4+ — the script relies on `declare -A` associative arrays (`vps-boot.sh:713-720`), `mapfile`, `BASH_REMATCH`, and `${var,,}` case conversion |
| Source | `vps-boot.sh`, 2595 lines, single file |
| Tests | `tests/test_vps_boot.sh`, 1817 lines, hand-rolled harness |
| Target OS | Ubuntu LTS (apt + systemd assumed throughout) |
| Versioning | No git tags. `v0.0.1` / `v0.0.2` / `v0.0.3` exist only as merge-commit subjects |

Runtime dependencies are the target host's system tooling, not vendored libraries:
`apt`/`dpkg`, `systemd` (`systemctl`, `journalctl`), `ufw`, `fail2ban`,
`openssh-server` (`sshd`, `ssh-keygen`), `iproute2` (`ss`), `sudo`/`visudo`,
`curl`, `awk`, `grep`, `sed`, `od`, `getent`, `tput`. `bl_update`
(`vps-boot.sh:1699-1706`) installs the subset that is not guaranteed present.

## Architecture

A single script read top to bottom, in ten ordered sections: header and shell
options, constants, UI library, component registry, components, baseline, SSH key
enrollment, validation helpers, flows, entry point.

**Component registry.** The toolchain is data, not control flow. `register()`
(`vps-boot.sh:726-741`) appends a key to the `COMPONENTS` array and populates
eight parallel associative arrays keyed by that id: `COMPONENT_NAME`, `COMPONENT_DESC`,
`COMPONENT_DEFAULT`, `COMPONENT_SCOPE`, `COMPONENT_GROUP`, `COMPONENT_INSTALL`,
`COMPONENT_CHECK`, `COMPONENT_SIGNIN`. Adding a tool means writing
`install_<key>`, `check_<key>`, and one `register` line — the wizard's
multi-select, Full install's defaults, the run loop, and the verifier all iterate
the registry, so no other plumbing changes. Registration order is run order.

`register <key> <name> <desc> <default 0|1> <scope> <group> <install_fn>
<check_fn> [signin_hint]` — the first eight arguments are required and fewer is
a hard error (`die`), so no component can carry an empty group. `signin_hint`
stays the trailing optional one.

`COMPONENT_GROUPS` fixes the six group names and their display order: `core`,
`languages`, `packaging`, `agents`, `cloud`, `infra`. The Components section is
laid out group by group under one `# ══ <group> ══` banner each, so registration
order matches group order.

Twenty-three components are registered, in run order:

| Group | Components (registry order) | Count |
|---|---|---|
| `core` | `sudo_nopasswd`, `tools`, `docker`, `gh` | 4 |
| `languages` | `node`, `python`, `go`, `java`, `rust` | 5 |
| `packaging` | `bun`, `pnpm`, `uv` | 3 |
| `agents` | `claude`, `opencode`, `codex`, `gemini`, `pi`, `hermes` | 6 |
| `cloud` | `vercel`, `neon`, `hostinger` | 3 |
| `infra` | `caddy`, `herdr` | 2 |

All default to on. `COMPONENT_SCOPE` is `system` for every component except
`hermes`, which is `user` and runs its installer through
`sudo -u "$USERNAME" -H bash`. That idiom carries a trap worth stating once:
`-H` sets `HOME` but inherits the *caller's* working directory, which is root's
`/root` at mode `700`. A user-scope step therefore starts in a directory it
cannot read, and anything touching `.` fails with `EACCES`. Every user-scope
body begins `cd "$HOME" || exit 1`. It is invisible in root-only mode, so only
a created-user install exercises it.

Only 22 of the 23 are ever offered in **root-only** mode:
`component_is_applicable` filters `sudo_nopasswd` out, since there is no
created user for the NOPASSWD rule to name. So `Full install`'s registry-computed
label reads "22 tools" and `core` reports 3 there, while a created-user install
offers, installs and checks all 23.

**Baseline.** Six functions — `bl_update`, `bl_unattended`, `bl_user`, `bl_ufw`,
`bl_ssh_harden`, `bl_fail2ban` — are mandatory, deliberately *not* registered, and
invoked in a hardcoded order by `cmd_install`. `bl_update`
now also installs `build-essential`, so a compiler no longer depends on Hermes
being selected. `bl_unattended` installs `unattended-upgrades` and enables the
security pocket only, `Automatic-Reboot` left `false`; it enables
`apt-daily-upgrade.timer` for future boots but deliberately without `--now` (see
"apt/dpkg lock handling" below). `bl_user` is the one conditional step, skipped
in root-only mode.

**apt/dpkg lock handling (issue #43).** `DPkg::Lock::Timeout` (written by
`install_apt_lock_timeout` to `APT_LOCK_CONFIG`) only bounds dpkg's own lock wait
*inside* an apt/dpkg invocation — it does nothing for `apt update`, which takes
`/var/lib/apt/lists/lock` before dpkg is ever invoked. On a fresh Ubuntu image
`apt-daily.timer`/`apt-daily-upgrade.timer` are enabled out of the box and fire on
a randomized delay after boot, so that lock can be held by an unrelated
background run right as the first component's `apt update` executes. Two
mitigations close this, both added for issue #43:
- `wait_for_apt` polls `fuser` on `/var/lib/apt/lists/lock` and
  `/var/lib/dpkg/lock-frontend` once a second, bounded by `APT_LOCK_TIMEOUT`
  (falling loudly through `warn` if the budget is exhausted), and is called
  immediately before every `apt update`/`apt upgrade`/`apt install` in the
  script. It is a no-op if `fuser` isn't on the host.
- `stop_apt_timers`/`restore_apt_timers` remove the race outright for the
  duration of an install: `cmd_install` stops both timers (and their services,
  to kill any run already in flight) before the first apt call, and restores
  them as soon as the last apt consumer is done — after `enroll_ssh_key` and
  *before* `do_check`. That ordering is load-bearing (issue #49): since
  `bl_unattended` enables `apt-daily-upgrade.timer` without `--now`, the timer
  is inactive for the whole window, so a verifier run inside it reports a false
  ✗ on every install. Closing the window early is safe because no `apt`
  invocation exists in `do_check` or in any `check_*`. The same pair also runs
  from `cmd_install_cleanup` on the `EXIT`/`HUP`/`INT`/`TERM` traps, so a killed
  run restores them too; both paths are idempotent, and a run killed *before*
  the traps are armed (SIGKILL, power loss) leaves the timers stopped — which is
  what `do_check_unattended` now reports as its own distinct failure rather than
  folding into "not configured".

**Flows.** `main` dispatches to `cmd_install`, `cmd_check`, or `cmd_help`.
`cmd_install` is wizard → confirm → run → `enroll_ssh_key` → `do_check`.
`cmd_check` reconstructs the component list from persisted state, then calls the
same `do_check`, so the inline and standalone verifier are one code path.

**Sourcing guard.** `vps-boot.sh:2512-2514` runs `main` only when the file is
executed rather than sourced, and the guard also treats an empty `BASH_SOURCE[0]`
as executed so `curl … | bash -s install` still works. This is what lets the test
harness `source` the script and call individual functions.

**Two user modes.** `configure_user_mode` (`:2064-2078`) sets `USERNAME=root` and
`CREATE_USER=0` for the default root-only path, or `CREATE_USER=1` for a created
sudo user. Mode is threaded through the rest of the script by branching on
`$USERNAME == "root"`: `component_is_applicable` filters `sudo_nopasswd` out of
root installs, `add_docker_group_if_needed` skips the group add, `bl_ssh_harden`
picks `PermitRootLogin yes` vs `no`, and several `check_*` functions branch on it.

## Data model & storage

No database. State is files on the target host, all of them env-overridable so the
test harness can redirect them into a temp directory (`vps-boot.sh:16-30`).

| Path | Constant | Purpose |
|---|---|---|
| `/etc/vps-boot/components` | `STATE_FILE` | Enabled component keys, one per line. Written at the end of the run phase; read by standalone `check` |
| `/tmp/vps-boot.log` | `LOG_FILE` | Per-step stdout+stderr, truncated at install start |
| `/etc/ssh/sshd_config.d/00-vps-boot.conf` | `SSHD_DROPIN` | The managed sshd settings — `Port`, `PermitRootLogin`, `PasswordAuthentication`, `KbdInteractiveAuthentication` |
| `/etc/ssh/sshd_config.bak.<epoch>` | — | Timestamped backup taken once by `bl_ssh_harden` |
| `/etc/sudoers.d/90-vps-boot-<user>` | `SUDOERS_DIR` | NOPASSWD rule from the `sudo_nopasswd` component |
| `/etc/apt/apt.conf.d/99-vps-boot-lock-timeout` | `APT_LOCK_CONFIG` | `DPkg::Lock::Timeout "180"`. Only covers dpkg's own lock wait, not the apt lists lock — see `wait_for_apt`. Transient — armed by an `EXIT` trap and removed when the run ends |
| `/etc/apt/apt.conf.d/20auto-upgrades` | `UNATTENDED_UPGRADES_CONFIG` | Enables periodic unattended upgrades from the security pocket only; `Automatic-Reboot` left `false`. Written by `bl_unattended` and persists after the run |
| `/usr/local/rustup`, `/usr/local/cargo` | `RUSTUP_HOME_DIR`, `CARGO_HOME_DIR` | System-wide rustup home and cargo home. `install_rust` installs into them and `check_rust` reads them, so the two cannot drift apart |
| `/etc/profile.d/{go,java,rust}.sh` | — | Login-shell drop-ins written by `install_go`, `install_java` and `install_rust`: `PATH` for Go, `JAVA_HOME` for the JDK, and `RUSTUP_HOME`/`CARGO_HOME`/`PATH` for the rustup shims. They are what make these three resolve for a created user, not only for root |

`/etc/sudoers.d/99-vps-boot-hermes` is a second, temporary sudoers rule written by
`install_hermes` and removed by a `RETURN` trap. It hardcodes its path
(`vps-boot.sh:1489`, `:1492`) rather than using `$SUDOERS_DIR`, so unlike every other
state path it is not redirectable under test.

The state file is the only thing that survives to inform a later `check`. When it
is absent, `cmd_check` falls back to checking every registered component.

## Auth

There is no application auth. The subject is the host's SSH access policy.

**During install**, `bl_ssh_harden` moves sshd to the chosen port and leaves
password authentication *on*, so the operator can still get in to push a key. Root
login is `yes` in root-only mode and `no` when a user was created.

**Lockdown** is a separate, opt-in step. `enroll_ssh_key` (`:2013-2058`) prints
copy-pasteable `ssh-copy-id` commands, then offers `ok` / `skip`. Choosing `ok`
does not by itself lock down — `authorized_keys` must be non-empty *and*
`ssh-keygen -l` must parse it as a real key. Only then does `lockdown_ssh` set
`PasswordAuthentication no`, `KbdInteractiveAuthentication no`, and
`PermitRootLogin prohibit-password` for root-only installs. A missing or malformed
key leaves password auth on and warns.

**Policy is verified against effective config, not the file.** `apply_sshd_policy`
(`:1915-1948`) writes the drop-in, then `validate_sshd_policy` runs `sshd -t` and
parses `sshd -T -C user=…,host=…,addr=…` output. That means a `Match` block
elsewhere in `sshd_config` cannot silently override the managed values. The policy
is checked twice when a user was created — once in the user's context and once in
root's (`:1873-1877`) — because `PermitRootLogin` only shows its true value in root's
context. It also asserts exactly one effective `Port`, and that at least one
effective `ListenAddress` is non-loopback (`validate_sshd_listeners`, `:1818-1858`),
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

Two install modes, `Full install` and `Custom`. `Full install` runs every
applicable default; its label and per-group counts are computed from the
registry (`full_install_option`), never enumerated, because a hardcoded list
rots as soon as a component is added. There is no third "baseline only" mode —
Custom plus the picker's `n` hotkey is the two-keystroke equivalent.

`prompt_multiselect` renders a **grouped grid**, not a flat list: the group name
in a left gutter, then up to three columns of `MSEL_CELL_W` (21), degrading to
two and then one as `term_cols` shrinks. Its state lives in `MSEL_*` globals so
the layout (`msel_layout`), the rendering (`msel_build` → `MSEL_LINES`) and the
2-D navigation (`msel_up`/`msel_down`/`msel_left`/`msel_right`) are unit-testable
without a tty. The redraw moves the cursor up by the number of lines actually
rendered, clamped to the terminal height (`msel_visible_rows`) — the previous
picker moved up one row per option, which corrupted the display as soon as the
block outgrew the screen.

Neither summary surface ever joins an unbounded list into one line, because a
wrapped remainder carries no rail prefix and breaks the left border.
`selection_summary` renders group counts for a full selection, and otherwise the
shorter of the skipped and selected halves, truncated with `+N more` to a
caller-supplied budget. Both the picker's collapse and the Confirm screen use it.

Terminal geometry goes through `term_cols` / `term_lines`, which validate
`tput` output and fall back to 80×24. No rendering code may declare a local
named `width`: these helpers are resolved dynamically, so a same-named local
would shadow a caller's or a test's value.

**Distribution** — `curl -fsSL https://raw.githubusercontent.com/julienlegoux/vps-boot/{main,develop}/vps-boot.sh | sudo bash -s install`.

**Third-party sources**, all fetched over HTTPS at install time:

| Component | Source |
|---|---|
| `tools` | Ubuntu archive (`jq`, `ripgrep`, `fd-find`, `htop`, `tree`); `fd` exposed via `update-alternatives` |
| `docker` | `download.docker.com` apt repo, keyring in `/etc/apt/keyrings/docker.asc` |
| `gh` | `cli.github.com` apt repo, keyring in `/usr/share/keyrings/` |
| `node` | NodeSource `setup_lts.x` script, piped to `bash` |
| `bun`, `pnpm`, `claude`, `opencode`, `codex`, `gemini`, `pi`, `vercel`, `neon` | npm registry, global installs (`bun`, `pnpm`, `@anthropic-ai/claude-code`, `opencode-ai`, `@openai/codex`, `@google/gemini-cli`, `@earendil-works/pi-coding-agent`, `vercel`, `neonctl`) |
| `python` | `ppa:deadsnakes/ppa` |
| `go` | `go.dev/VERSION?m=text` then the matching tarball into `/usr/local` |
| `java` | `apt`, probed descending for the newest installable LTS `openjdk-NN-jdk-headless` |
| `rust` | `sh.rustup.rs`, piped to `sh` with `RUSTUP_HOME`/`CARGO_HOME` pinned to `/usr/local/rustup` and `/usr/local/cargo` (`RUSTUP_HOME_DIR`, `CARGO_HOME_DIR`) plus `-y --no-modify-path`; a `/etc/profile.d/rust.sh` drop-in exports them and extends `PATH` |
| `uv` | `astral.sh/uv/install.sh`, piped to `sh` with `UV_INSTALL_DIR=/usr/local/bin` |
| `hermes` | NousResearch `install.sh` from GitHub raw, piped to `bash` |
| `hostinger` | GitHub releases API (`hostinger/api-cli`), architecture-matched tarball verified against the release's `checksums.sha256` before installing to `/usr/local/bin` |
| `caddy` | `dl.cloudsmith.io/public/caddy/stable` apt repo, keyring in `/usr/share/keyrings/`; installs and enables the service but opens no firewall ports |
| `herdr` | `herdr.dev/install.sh`, piped to `sh` with `HERDR_INSTALL_DIR=/usr/local/bin` |

`bun`, `pnpm`, `claude`, `opencode`, `codex`, `gemini`, `pi`, `vercel` and `neon`
are registered `system` scope but install through `npm -g`, so all nine have a
hard ordering dependency on `node` appearing earlier in the registry. The group
order holds that for free: `node` sits in `languages`, ahead of `packaging`,
`agents` and `cloud`.

`herdr` and `uv` both pin their upstream installer's target directory. The
default for each is `$HOME/.local/bin`, which is not on `PATH` for a fresh
root-only box, so `HERDR_INSTALL_DIR=/usr/local/bin` and
`UV_INSTALL_DIR=/usr/local/bin` make the binaries resolve for root and any
created user alike. `rust` needs the same guarantee but cannot get it from an
install dir — rustup's binaries in `$CARGO_HOME_DIR/bin` are *shims* that
resolve the default toolchain out of `RUSTUP_HOME` at run time — so the
profile.d drop-in exports the variable rather than only extending `PATH`, and
`check_rust` sets it explicitly because it runs before any login shell has
sourced that drop-in.

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
actually bind after `systemctl start` (polled up to 5×1s), a concurrent
apt-daily(-upgrade) run holding the apt lists lock (`wait_for_apt` plus
`stop_apt_timers`/`restore_apt_timers` around the whole install — `DPkg::Lock::Timeout`
180s alone does not cover this lock), and a missing `/run/sshd` blocking `sshd -t`
on hosts where `ssh.service` never started.

## Testing infrastructure

One harness, `tests/test_vps_boot.sh`, run manually:

```bash
bash tests/test_vps_boot.sh              # all
bash tests/test_vps_boot.sh <filter>     # or TEST_FILTER=<substring>
```

101 cases, registered as explicit `run_test "<label>" <fn>` lines at the bottom of
the file. Output is TAP-flavoured (`ok - <label>` / `not ok - <label>`), with a
`N passed, M failed` summary and a non-zero exit when anything failed.

**The suite needs a real Linux host to pass in full.** Twelve cases require
root, a writable `/run` and an `sshd` binary — the SSH-policy and sudoers
groups, and the two end-to-end `cmd_install` flows. On a developer workstation
without those they fail regardless of the branch, so a raw failure count is not
a regression signal; compare the *set* of failing labels against the
integration branch instead.

The harness exercises the real script rather than a copy: it exports every
`VPS_BOOT_*` path constant into a `mktemp -d` sandbox, writes a fake
`sshd_config` with an `Include` line, then `source`s `vps-boot.sh` and calls
functions directly. Mocking is done by redefining shell functions and commands
(`chmod() { return 23; }`, stubbed `step_run`, stubbed `bl_*`) inside the subshell
`run_test` spawns, so overrides do not leak between cases.

Coverage is concentrated where the risk is. SSH policy is the largest group —
`Match`-block overrides, unexpected listener ports, loopback-only listeners, extra
ports, reload failure, and drop-in restore on every failure path. Next is the
picker: `msel_layout`, `msel_build`, the 2-D navigation, column degradation,
`vis_len`, and `selection_summary`'s budget on both its full and partial
branches. The rest cover the sourcing guard, `step_run` fail-fast, APT fragment
lifecycle, both install flows end to end, sudoers validation, the registry
contract (every key names real functions, a known scope and one of the six
groups), `check_*` version parsing against the verbatim strings the tools print
on Ubuntu 24.04, and one case asserting the README documents current behaviour.

Not covered: the network-dependent `install_*` bodies, and anything requiring a
real Ubuntu host — which is why an epic that changes the registry ends with a
manual acceptance run against one.

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

**Trap-scoped cleanup.** `cmd_install` arms a single `EXIT` trap
(`cmd_install_cleanup`, which restores the apt timers and removes the APT lock
fragment) *before* `stop_apt_timers`/`install_apt_lock_timeout` run, so an abort
between arming and either setup step still restores state. The happy path calls
both cleanups directly at the end and disarms the trap. `install_hermes` uses a
`RETURN` trap for its temporary sudoers
rule.

**Secret handling.** `USER_PASSWORD` lives in a shell variable, is passed to
`chpasswd` over a pipe rather than the command line, and is cleared immediately
after the run phase (`vps-boot.sh:2247`).

**Presentation.** All user-visible output goes through the UI helpers; ANSI colors
are set to empty strings when stdout is not a TTY (`:33-45`).
