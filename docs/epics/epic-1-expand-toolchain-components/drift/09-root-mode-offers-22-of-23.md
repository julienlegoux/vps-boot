---
type: Drift
title: "Root-only Full install offers 22 of the 23 registered components"
description: "The epic's acceptance criteria ask for a ✓ on all 23 components in root-only mode, but component_is_applicable deliberately filters sudo_nopasswd out of that mode, so 22 is the correct number there."
tags: [epic-1, drift]
timestamp: 2026-08-17T01:30:00Z
epic: 1
issue: 09
---

# Root-only Full install offers 22 of the 23 registered components

- **Decided**: [Epic 1](../EPIC_1.md) acceptance criterion 2 — "On a fresh
  Ubuntu 24.04 host, root-only mode, **Full install**: all 23 components
  install and `check` reports `✓` for each" — restated in
  [issue 09](../issues/09-verify-and-reanchor-docs.md) as "a `✓` for all 23
  components" and "the number 23 … agree across `README.md`,
  `docs/planning/SPECS.md`, `.claude/CLAUDE.md` and the wizard's own computed
  label".
- **Actual**: 23 components are registered, but root-only mode offers,
  installs and checks **22**. `component_is_applicable`
  (`vps-boot.sh:2065-2068`) filters `sudo_nopasswd` out whenever
  `USERNAME == "root"`, and `full_install_keys` / `cmd_check` both iterate
  through that filter. The wizard's computed label reads
  `everything — 22 tools` with `core 3`, and the acceptance run's `check`
  reported `37 passed, 0 failed, 1 warning(s)` — 15 baseline assertions plus
  22 components. All 23 appear only in created-user mode.
- **Because**: this is not a defect and nothing was worked around. A
  `NOPASSWD` sudoers rule needs a non-root user to name; `install_sudo_nopasswd`
  writes `/etc/sudoers.d/90-vps-boot-$USERNAME`, which for root would be a
  rule granting root passwordless sudo to itself. The filter predates this
  epic (it is described in `SPECS.md` under "Two user modes" and in
  `.claude/CLAUDE.md` under "Optional user creation") and issue 01 carried it
  forward unchanged. What is wrong is the acceptance criterion, which counts
  the registry and assumes the number reaches the screen in both modes.
- **Disposition**: accepted — the code is right, the criterion is imprecise.
  `SPECS.md` and `README.md` now state both numbers explicitly (23 registered,
  22 applicable in root-only mode) rather than a single count that is wrong in
  one mode. Recorded rather than silently reinterpreted, because "all 23
  verified" is exactly the sort of claim a later reader would check against a
  transcript showing 22.
- **Revisit when**: a component other than `sudo_nopasswd` becomes
  mode-dependent. `component_is_applicable` is currently a single hardcoded
  key; a second one would justify a `COMPONENT_APPLICABLE` predicate in the
  registry and would make "the count" genuinely per-mode data rather than a
  one-off subtraction.
- **Evidence**:
  [run-1-root-full-check.txt](../verification/run-1-root-full-check.txt),
  [run-1-wizard-80x24.md](../verification/run-1-wizard-80x24.md), PR #42
