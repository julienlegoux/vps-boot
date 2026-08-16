---
type: Issue
title: "Add COMPONENT_GROUP and reorder the registry by group"
description: "Add a COMPONENT_GROUP field to register(), assign a group to each of the twelve existing components, reorder the Components section into the six groups, and add the registry-invariant test."
tags: [epic-1]
timestamp: 2026-08-17T12:40:00Z
epic: 1
issue: 01
slug: registry-groups-and-reorder
size: M
status: pr-open
gh_issue: 19
gh_pr: 34
depends_on: []
resource: https://github.com/julienlegoux/vps-boot/issues/19
---

# Add COMPONENT_GROUP and reorder the registry by group

## Summary

Every other component issue in this epic adds a `register` line, and the wizard
rework (issue 08) lays the picker out by group. Both need the registry to carry a
group first. This issue does that mechanism change once, on the twelve components
that exist today, so the nine issues after it only add rows.

It also lands the epic's one new test case — the registry invariant — while the
registry is the only thing in the diff, which is the cheapest moment to prove the
`install_x` / `check_x` / `register x` triple actually holds.

## Scope

- Add `declare -A COMPONENT_GROUP=()` alongside the seven existing parallel
  arrays (`vps-boot.sh:384-391`) and extend `register()` (`vps-boot.sh:396-407`)
  to populate it. Group is a **required** argument; `signin_hint` stays the
  trailing optional one. Update the signature comment at `vps-boot.sh:393-395`.
- Assign a group to each of the twelve current components, using the six values
  the epic fixes: `core`, `languages`, `packaging`, `agents`, `cloud`, `infra`.
  Only four of the six are populated at this point — `cloud` has no members until
  issue 06 and `infra` gains `caddy` in issue 07; `herdr` is `infra` from here.
- Reorder the component blocks in the Components section
  (`vps-boot.sh:411-731`) so registration order matches group order. Current
  order is `sudo_nopasswd, docker, gh, node, bun, pnpm, claude, opencode, python,
  go, hermes, herdr`; target order for the existing twelve is:

  | Group | Order after this issue |
  |---|---|
  | `core` | `sudo_nopasswd`, `docker`, `gh` |
  | `languages` | `node`, `python`, `go` |
  | `packaging` | `bun`, `pnpm` |
  | `agents` | `claude`, `opencode`, `hermes` |
  | `infra` | `herdr` |

  Move whole blocks (banner comment + `install_x` + `check_x` + `register x`);
  do not edit their bodies. The npm-based components (`bun`, `pnpm`, `claude`,
  `opencode`) still land after `node`, which is what the ordering has to preserve
  — the group order was chosen so that constraint holds for free.
- Add one test case to `tests/test_vps_boot.sh` asserting, for every key in
  `COMPONENTS`: `declare -F "${COMPONENT_INSTALL[$key]}"` and
  `declare -F "${COMPONENT_CHECK[$key]}"` both resolve, `COMPONENT_SCOPE[$key]`
  is `system` or `user`, and `COMPONENT_GROUP[$key]` is one of the six values.
  Register it with a `run_test` line in the block at
  `tests/test_vps_boot.sh:628-659`.
- Update `.claude/CLAUDE.md`'s "Adding a new component" worked example and its
  `register` argument annotation, and `docs/planning/SPECS.md`'s registry
  paragraph (seven arrays → eight, and the run order list).

## Out of scope

- Any new component. The registry holds twelve after this issue; the eleven
  additions arrive in issues 03–07.
- `COMPONENT_REQUIRES` / declared dependencies — explicitly out of the epic.
  Ordering stays positional.
- The picker and the mode labels that consume the group (issue 08). Nothing
  reads `COMPONENT_GROUP` yet after this issue except the new test, and that is
  fine.
- Re-anchoring SPECS.md's line numbers past the moved blocks. The reorder shifts
  them, and every following issue shifts them again; the sweep is issue 09.

## Acceptance criteria / Definition of done

- [ ] `bash tests/test_vps_boot.sh` passes, reporting **33 passed, 0 failed** (32
      existing + the registry invariant).
- [ ] The new case fails when deliberately broken — e.g. temporarily registering
      a component with group `misc`, or with a `check_fn` name that has no
      function — and passes again when reverted. Verify this before opening the
      PR.
- [ ] `bash -n vps-boot.sh` is clean and `bash tests/test_vps_boot.sh
      cmd_install` still passes both install-flow cases, which exercise the run
      loop over the reordered registry.
- [ ] `register` called with the old seven-argument form is a hard error, not a
      silently empty group: no call site is left un-migrated (grep for
      `^register ` and count 12 lines, each carrying a group).
- [ ] `.claude/CLAUDE.md` and `docs/planning/SPECS.md` are updated in the same
      commit as the code.

## Relevant files / areas

- `vps-boot.sh:384-391` — the parallel associative arrays.
- `vps-boot.sh:393-407` — `register()` and its signature comment.
- `vps-boot.sh:411-731` — the Components section; every block moves or gains a
  group argument. Existing `register` lines: `:446`, `:486`, `:511`, `:530`,
  `:547`, `:564`, `:579`, `:597`, `:656`, `:680`, `:710`, `:731`.
- `tests/test_vps_boot.sh:628-659` — the `run_test` registration block; an
  unregistered case silently never runs.
- `.claude/CLAUDE.md` — "Component registry" and "Adding a new component".
- `docs/planning/SPECS.md` — "Component registry" under Architecture.

## Dependencies

- **Blocked by**: none.
- **Blocks**: issues 03, 04, 05, 06, 07 (each adds a `register` line that needs
  the group argument) and issue 08 (the picker groups by this field).

## PR size note

Target ~500 changed lines; if this grows past ~1000, split it before opening the
PR. The reorder is the bulk of the diff — roughly 200 moved lines — so keep the
moves pure: any edit to a moved block's body belongs in a different PR.
