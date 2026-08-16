---
type: Epic
title: "Expand the toolchain component registry"
description: "Take vps-boot.sh from twelve components to twenty-three, harden the baseline with build-essential and automatic security updates, and rebuild the component picker so the list still fits a terminal."
tags: [epic, change]
timestamp: 2026-08-16T10:05:00Z
epic: 1
slug: expand-toolchain-components
status: open
gh_issue: 18
milestone: 1
resource: https://github.com/julienlegoux/vps-boot/issues/18
source: docs/planning/changes/change-1-expand-toolchain-components/index.md
---

# Epic 1: Expand the toolchain component registry

## Goal

Add eleven components to `vps-boot.sh` — the Vercel, Hostinger and Neon CLIs, a
JDK, Rust, uv, Caddy, the Codex, Gemini and pi agents, and a `tools` bundle —
taking the registry from twelve to twenty-three. Close two gaps the audit found
in the baseline (`build-essential`, automatic security updates), and rebuild the
wizard's component picker, which does not survive twenty-three items.

## Scope

**Eleven new components.** Each is the standard triple — `install_<key>`,
`check_<key>`, one `register` line — in the Components section, grouped by kind
in registration order. Every `check_*` must print a real version string.

| Key | Install | Notes |
|---|---|---|
| `tools` | `apt install jq ripgrep fd-find htop tree` | plus `update-alternatives` exposing `fdfind` as `fd`; registers **before** `hermes` |
| `vercel` | `npm -g vercel` | hint: `vercel login --no-browser` (bare `vercel login` hangs headless) |
| `hostinger` | GitHub releases tarball → `/usr/local/bin` | resolve latest tag from the API, map `dpkg --print-architecture`, **verify `checksums.sha256`**; mirrors `install_go` |
| `neon` | `npm -g neonctl` | check probes `neonctl`, not its second binary name `neon` |
| `pi` | `npm -g @earendil-works/pi-coding-agent` | **not** `pi.dev/install.sh` — that wrapper prompts for a `PATH` edit and would hang `step_run` |
| `codex` | `npm -g @openai/codex` | |
| `gemini` | `npm -g @google/gemini-cli` | |
| `java` | probe newest installable **LTS** `openjdk-NN-jdk-headless` | `apt --dry-run` descending over LTS majors only — `(n - 21) % 4 == 0`, i.e. 17/21/25/29/33; + `/etc/profile.d/java.sh` exporting `JAVA_HOME`; check redirects `2>&1` and asserts `javac` |
| `rust` | `rustup` with `-y --no-modify-path` | `RUSTUP_HOME=/usr/local/rustup`, `CARGO_HOME=/usr/local/cargo`, + `/etc/profile.d/rust.sh`; bare `rustup` is interactive and would hang `step_run` |
| `uv` | `astral.sh/uv/install.sh` with `UV_INSTALL_DIR=/usr/local/bin` | mirrors `install_herdr`'s pinned-dir fix |
| `caddy` | official apt repo (`dl.cloudsmith.io/public/caddy/stable`) | **opens no firewall ports**; check must report the UFW state for 80/443, not just `systemctl is-active` |

**Registry grouping.** A new `COMPONENT_GROUP` field, six values:

| Group | Components |
|---|---|
| `core` (4) | `sudo_nopasswd`, `tools`, `docker`, `gh` |
| `languages` (5) | `node`, `python`, `go`, `java`, `rust` |
| `packaging` (3) | `bun`, `pnpm`, `uv` |
| `agents` (6) | `claude`, `opencode`, `codex`, `gemini`, `pi`, `hermes` |
| `cloud` (3) | `vercel`, `hostinger`, `neon` |
| `infra` (2) | `caddy`, `herdr` |

**Two baseline changes.** `build-essential` joins `bl_update`'s package list —
it arrives today only as a Hermes side effect, so unticking Hermes silently
removes the compiler. And a new `bl_unattended` step after `bl_update` installs
`unattended-upgrades` and writes `/etc/apt/apt.conf.d/20auto-upgrades` for the
security pocket, with `Automatic-Reboot` left `false`. This is the only work in
the epic that touches the hardcoded baseline sequence (`vps-boot.sh:1269-1275`).

**Wizard rework.** `QuickStart` becomes `Full install`; two modes, with `a`
(all) and `n` (none) hotkeys in the picker replacing the need for a third
"baseline only" mode. Mode labels carry counts computed from the registry —
never a hardcoded enumeration, which is how the current label came to advertise
five tools while installing twelve.

`prompt_multiselect` is rewritten as a grouped multi-column grid (three columns
of width 21, degrading via `tput` on narrow terminals). This fixes a real
defect, not just readability: the current implementation redraws with a blind
`printf '\033[%dA' "$n"`, which corrupts the display once the block scrolls —
at twenty-three items it is 25 rows, past the fold on an 80×24 terminal.

Both summary surfaces stop joining unbounded lists into one line: the picker's
collapse and the Confirm screen (`vps-boot.sh:1240-1246`) render group counts
for a full selection, and list the *skipped* items when that is the shorter
half.

**Two fixes from the version audit.** `check_claude` gains a version string — it
is the only check of the twelve that reports none. Nothing else is stale.

**One new test.** A registry-invariant case: for every key in `COMPONENTS`,
assert `COMPONENT_INSTALL`/`COMPONENT_CHECK` name functions `declare -F` finds,
`COMPONENT_SCOPE` is `system` or `user`, and `COMPONENT_GROUP` is one of the six.

**Documentation, in the same commit as the code.** `README.md`'s toolchain
table; `SPECS.md`'s component list, count, third-party source table and the line
anchors past every insertion point.

## Out of scope

- **Declared component dependencies** (`COMPONENT_REQUIRES`). The
  `node`-before-npm ordering stays positional. Follow-up issue.
- **CI.** Nothing runs the test suite automatically, including the case this
  epic adds. Follow-up issue.
- **Version pinning and a release process.** The audit is the evidence that
  resolving newest-at-install-time has cost nothing.
- **A Node version guard.** Investigated and dropped — three existing defences
  make its failure mode unreachable.
- **Re-run idempotency** on an already-provisioned host.
- **`install_hermes`' hardcoded sudoers path.**
- **Token and credential provisioning.** Out on the merits, not just scope:
  writing a Hostinger token that can rebuild a VPS to disk during a provisioning
  run needs its own change.
- **Further wizard UI work** beyond the picker and the two summary surfaces.
- **Tailscale, Wrangler, Deno, mise/asdf, Terraform, AWS CLI, native
  Postgres/Redis** — considered and excluded.
- **A swap file.** A real gap for a 2-core VPS that now compiles Rust, but a
  `bl_*` change belonging to a hardening epic.

## Acceptance criteria

1. `bash tests/test_vps_boot.sh` passes — 33 cases (32 existing + the registry
   invariant).
2. On a fresh Ubuntu 24.04 host, root-only mode, **Full install**: all 23
   components install and `vps-boot.sh check` reports `✓` for each, exit 0.
3. Created-user mode spot check: `install` completes and the new components
   resolve on `PATH` **as the created user** — where `java`'s and `rust`'s
   `/etc/profile.d` drop-ins and `uv`'s pinned install dir either work or don't.
4. Every `check_*` prints a real version, never `?` — including `check_claude`.
5. The wizard renders correctly at 23 components on an **80×24** terminal:
   the picker, its collapse summary, and the Confirm screen.
6. `check_caddy` reports the UFW state for 80/443, not just the service state.
7. `check` surfaces unattended-upgrades status and `/var/run/reboot-required`.
8. `README.md` and `SPECS.md` are updated in the same commit as the code.

## Dependencies

None.

## Context

- [Technical specs](../../planning/SPECS.md)
- [Conventions](../../planning/CONVENTIONS.md)
- [Change 1 ledger](../../planning/changes/change-1-expand-toolchain-components/index.md)
  — 20 decisions, the rationale behind every line above

## Notes

**Interactive installers are the recurring hazard.** Three of the new components
ship upstream installers that prompt: `pi.dev/install.sh` (asks to edit `PATH`),
bare `rustup` (menu), and Hermes' installer (offers `ripgrep`/`ffmpeg`). A
prompt inside a `step_run` body hangs the run with no visible cause, because
stdout is redirected to the log. Every install path chosen here avoids the
prompt rather than trying to answer it. Registering `tools` before `hermes` also
removes the reason Hermes' `ripgrep` prompt would fire.

**The Node dependency is now nine components deep** — `bun`, `pnpm`, `claude`,
`opencode`, `vercel`, `neon`, `pi`, `codex`, `gemini` all install via `npm -g`
and must register after `node`. Their `engines.node` floors are `pi` ≥22.19
(highest), `claude` ≥22.0, `neonctl` ≥20.19, `gemini` ≥20, `codex` ≥16, against
NodeSource Active LTS 24.19.0. This is safe and needs no guard: Active LTS only
moves forward, `setup_lts.x` exits non-zero on every failure path, and its apt
pin (`Pin-Priority: 600` on `deb.nodesource.com`) blocks any fallback to Ubuntu
noble's own `nodejs` 18.19.1, which would be below every floor. Recorded so the
next reader does not re-derive it.

**Caddy is the one component that argues with the baseline.** `apt install
caddy` starts and enables a systemd service listening on `:80`, which UFW
denies — so `systemctl is-active` says `active` on a server nobody can reach.
The check must look at both, and emit a `note` (not a `ko`): the closed firewall
is correct behaviour, not a defect. A wizard prompt offering to open 80/443 was
the runner-up and is worth revisiting while the wizard is already being touched.

**The Hostinger token is account-wide.** The same credential that lists a VPS
can rebuild it. The sign-in hint should say so.

**Java needs the newest LTS — which is neither the distro default nor the newest
package.** Three different versions hide behind "current Java" here, and the
component has to pick the third:

- `default-jdk` on noble → **21**, one LTS behind;
- newest `openjdk-NN` the archive will install → **25** today, but only because
  Ubuntu has backported *only* LTS JDKs into noble (`17`, `21`, `25` present;
  `22`, `23`, `24`, `26` absent). That is Ubuntu's backport policy, not a
  guarantee, and Ubuntu does package feature releases in its interim distros;
- newest **LTS** → **25**, and the only one of the three that stays correct.

Hence the `(n - 21) % 4 == 0` filter: since Java 17 the LTS cadence is four
feature releases (two years), so 17/21/25/29/33 are exactly the LTS majors, and
the rule needs no bumping in 2027. A six-month feature release on a box meant to
run unattended is the wrong default.

This trap is unique to Java. For `go` and `python` — whose probing idiom was
borrowed — "default", "newest" and "newest LTS" collapse into one version, which
is why the idiom transplanted badly and needed two corrections. See
[decision 05](../../planning/changes/change-1-expand-toolchain-components/05-java-jdk.md),
which keeps both superseded verdicts as history.

**`fd-find` installs its binary as `fdfind`** on Debian/Ubuntu, not `fd`.

**Sizing.** Roughly 400 lines added to `vps-boot.sh` (1539 today), most of it
eleven near-identical component blocks. The picker rewrite and the
`bl_unattended` baseline step are the two pieces with real design content and
should be separate issues from the component bulk.
