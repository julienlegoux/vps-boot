---
type: Drift
title: "vps-boot — Drift"
description: "Standards this codebase has drifted from, and why"
tags: [planning, drift]
timestamp: 2026-08-17T07:48:15Z
---

# Drift

Standards the implementation diverged from, promoted from the per-issue drift
records each epic leaves behind. Append-only, newest epic first: an entry that
stops being true becomes `resolved (<date>)` rather than disappearing. Read this
alongside [SPECS.md](SPECS.md) and [CONVENTIONS.md](CONVENTIONS.md) — a decided
standard plus its live drift is what the code actually looks like.

## Epic 1: Expand the toolchain component registry

### 09 — Root-only Full install offers 22 of the 23 registered components

- **Decided**: [Epic 1](../epics/epic-1-expand-toolchain-components/EPIC_1.md)
  acceptance criterion 2 — "root-only mode, **Full install**: all 23 components
  install and `check` reports `✓` for each" — restated in
  [issue 09](../epics/epic-1-expand-toolchain-components/issues/09-verify-and-reanchor-docs.md)
  as "a `✓` for all 23 components".
- **Actual**: 23 components are registered, but root-only mode offers, installs
  and checks **22**. `component_is_applicable` filters `sudo_nopasswd` out
  whenever `USERNAME == "root"`, and `full_install_keys` / `cmd_check` both
  iterate through that filter. The wizard's computed label reads
  `everything — 22 tools`; all 23 appear only in created-user mode.
- **Because**: not a defect and nothing was worked around. A `NOPASSWD` sudoers
  rule needs a non-root user to name — `install_sudo_nopasswd` writes
  `/etc/sudoers.d/90-vps-boot-$USERNAME`, which for root would grant root
  passwordless sudo to itself. The filter predates this epic (described in
  [SPECS.md](SPECS.md) under *Two user modes*). The acceptance criterion is what
  was wrong: it counts the registry and assumes the number reaches the screen in
  both modes.
- **Disposition**: accepted — the standard was corrected in the same PR:
  [SPECS.md:79](SPECS.md) and `README.md` now state both numbers explicitly
  (23 registered, 22 applicable in root-only mode) instead of a single count that
  is wrong in one mode.
- **Revisit when**: a component other than `sudo_nopasswd` becomes
  mode-dependent. `component_is_applicable` is currently a single hardcoded key;
  a second one justifies a `COMPONENT_APPLICABLE` predicate in the registry,
  making the count genuine per-mode data rather than a one-off subtraction.
- **Evidence**:
  [drift record](../epics/epic-1-expand-toolchain-components/drift/09-root-mode-offers-22-of-23.md),
  PR #42

### 09 — The documented user-scope idiom starts in a directory the user cannot read

- **Decided**: [`.claude/CLAUDE.md`](../../.claude/CLAUDE.md), *Conventions →
  Scope*: user-scope work inside an install fn runs through
  `sudo -u "$USERNAME" -H bash <<'EOF' … EOF`; restated in
  [SPECS.md](SPECS.md) under *Architecture* as how `hermes` — the registry's only
  `user`-scope component — runs its installer.
- **Actual**: that idiom is incomplete. `-H` sets `HOME` but the working
  directory is inherited from the caller, and the caller is root sitting in
  `/root` at mode `700`, so the user-scope shell begins where `$USERNAME` cannot
  stat. The created-user acceptance run died at Hermes, 22 of 23 components in:
  `error: failed to query metadata of symlink /root/.venv: Permission denied
  (os error 13)` — the Hermes installer drives uv, which probes the working
  directory for `uv.toml` and `.venv` before anything else.
- **Because**: verified on the host. `sudo stat -c '%a %U' /root` → `700 root`;
  `sudo bash -c 'cd /root && sudo -u devuser -H bash -c "ls -a ."'` →
  `ls: cannot access '.': Permission denied`; the same uv command fails from
  `/root` and succeeds from `/home/devuser`. Root-only mode cannot expose it —
  there `$USERNAME` *is* root — which is why it survived eight PRs and a clean
  root-only acceptance run.
- **Disposition**: resolved (2026-08-17) — the standard was wrong, so the
  standard changed. Every user-scope body now begins `cd "$HOME" || exit 1`;
  `install_hermes`'s body moved into `hermes_user_script` so the suite executes
  it against a stubbed installer and asserts the resulting working directory;
  `check_hermes` got the same treatment. CLAUDE.md and SPECS.md now state the
  `cd` as mandatory, with the error text and the reason it is invisible in
  root-only mode.
- **Revisit when**: a second `user`-scope component is registered. One call site
  is a convention; two is a helper — `run_as_user()` wrapping the
  `sudo -u … -H` invocation with the `cd` built in would make the trap
  unwritable rather than merely documented.
- **Evidence**:
  [drift record](../epics/epic-1-expand-toolchain-components/drift/09-user-scope-idiom-inherits-root-cwd.md),
  PR #42
