---
type: Issue
title: "Add build-essential and unattended-upgrades to the baseline"
description: "Move build-essential into bl_update's package list and add a bl_unattended baseline step that configures automatic security updates, with both surfaced by the verifier."
tags: [epic-1]
timestamp: 2026-08-17T11:00:00Z
epic: 1
issue: 02
slug: baseline-build-essential-auto-updates
size: S
status: open
gh_issue: 20
depends_on: []
resource: https://github.com/julienlegoux/vps-boot/issues/20
---

# Add build-essential and unattended-upgrades to the baseline

## Summary

Two gaps the audit found in the mandatory baseline. A compiler is on the box
today only as a side effect of the Hermes installer, so unticking Hermes silently
removes it — every later component that builds native code then fails for a
reason nobody can see. And nothing applies security updates after the install
run, on a host explicitly meant to be left unattended.

This is the only work in the epic that touches the hardcoded baseline sequence
(`vps-boot.sh:1269-1275`), which is why it is its own issue and not folded into a
component.

## Scope

- Add `build-essential` to `bl_update`'s `apt install -y` list
  (`vps-boot.sh:766-772`).
- Add a `bl_unattended` baseline function in the Baseline section, next to the
  other `bl_*` steps, that installs `unattended-upgrades` and writes
  `/etc/apt/apt.conf.d/20auto-upgrades` enabling the **security pocket** only,
  with `Unattended-Upgrade::Automatic-Reboot "false";`. Follow the repo's
  transactional write pattern — `mktemp` beside the target, write, `chmod`,
  `mv -f`, `rm -f` the candidate on every failure branch.
- Wire it into the baseline sequence in `cmd_install` as
  `step_run "Automatic security updates" bl_unattended`, placed **after**
  `bl_update` (`vps-boot.sh:1269`) and before `bl_user`. It is mandatory and
  deliberately not registered, like every other `bl_*`.
- Extend `do_check` (`vps-boot.sh:1339-1489`), in the baseline block before the
  `# ── components ──` loop, with two lines: whether unattended-upgrades is
  configured and its timer active (`ok`/`ko`), and whether
  `/var/run/reboot-required` exists — the latter as a `note`, not a `ko`. A
  pending reboot is information, not a defect, and per CONVENTIONS.md choosing
  `ko` where `note` belongs turns an operator's informed state into a failed
  health check.
- Document both in `README.md`'s baseline table (rows "System update" and a new
  automatic-updates row, `README.md:29-35`) and in `docs/planning/SPECS.md` —
  the baseline is described as *five* functions in two places (Architecture and
  the `bl_*` list); it becomes six.

## Out of scope

- The `tools` component (`jq`, `ripgrep`, `fd`, `htop`, `tree`) — issue 03. Only
  the compiler moves into the baseline here.
- `Automatic-Reboot "true"` or any reboot scheduling. Decided false.
- A swap file — a real gap for a 2-core box that now compiles Rust, but the epic
  puts it in a hardening epic, not this one.
- Removing Hermes' incidental `build-essential` install. Its installer keeps
  doing whatever it does; this issue only stops the box depending on it.
- Re-anchoring SPECS.md's line numbers past the moved blocks. The reorder
  shifts them, and every following issue shifts them again; the sweep is
  issue 09.

## Acceptance criteria / Definition of done

- [ ] `bash tests/test_vps_boot.sh` passes with no regressions — the two
      install-flow cases (`test_cmd_install_root_quickstart_flow`,
      `test_cmd_install_created_user_custom_flow`) stub `bl_*` functions, so
      confirm the new step is stubbed the same way as its siblings rather than
      hitting apt.
- [ ] `bash -n vps-boot.sh` is clean.
- [ ] `grep -c build-essential vps-boot.sh` shows it in `bl_update`'s list.
- [ ] On a fresh Ubuntu 24.04 host: `apt-config dump | grep -i
      Unattended-Upgrade` shows the security origin enabled,
      `/etc/apt/apt.conf.d/20auto-upgrades` exists with mode 0644, and
      `systemctl is-enabled apt-daily-upgrade.timer` reports `enabled`.
- [ ] `vps-boot.sh check` prints a line for unattended-upgrades and, when
      `/var/run/reboot-required` is present, a `!` note rather than a `✗` —
      exit code still 0 in that state.
- [ ] `README.md` and `docs/planning/SPECS.md` are updated in the same commit as
      the code.

## Relevant files / areas

- `vps-boot.sh:766-772` — `bl_update`.
- `vps-boot.sh:733-1038` — the Baseline section, where `bl_unattended` goes.
- `vps-boot.sh:1269-1275` — the hardcoded baseline sequence in `cmd_install`.
- `vps-boot.sh:1424-1452` — the UFW/fail2ban block in `do_check`, immediately
  before the component loop.
- `tests/test_vps_boot.sh:144-263` — the install-flow fixtures that stub `bl_*`.
- `README.md:29-35`, `docs/planning/SPECS.md` (Architecture → Baseline, and the
  data-model path table).

## Dependencies

- **Blocked by**: none. This issue touches the baseline only and never the
  registry, so it can run in parallel with issue 01.
- **Blocks**: nothing.

## PR size note

If this grows past ~1000, split it before opening the PR. This one should land
well under 150.
