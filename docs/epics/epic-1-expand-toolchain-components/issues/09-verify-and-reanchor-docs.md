---
type: Issue
title: "Verify the 23-component install and re-anchor the docs"
description: "Run the epic's acceptance matrix on a fresh Ubuntu 24.04 host in both user modes, then re-anchor SPECS.md's line numbers and reconcile the component counts across README, SPECS and CLAUDE.md."
tags: [epic-1]
timestamp: 2026-08-17T00:35:00Z
epic: 1
issue: 09
slug: verify-and-reanchor-docs
size: S
status: in-progress
gh_issue: 27
depends_on: [1, 2, 3, 4, 5, 6, 7, 8]
resource: https://github.com/julienlegoux/vps-boot/issues/27
---

# Verify the 23-component install and re-anchor the docs

## Summary

The epic's acceptance criteria include things no single issue can prove on its
own: that all 23 components install and verify on a real host, that the wizard
renders at 23 items rather than at whatever count existed when issue 08 merged,
and that the docs describe one coherent registry rather than eight PRs' worth of
partial edits.

`docs/planning/SPECS.md` cites line numbers throughout — `vps-boot.sh:396-407`,
`:1269-1275`, `:385-391` and a dozen more. Every issue in this epic shifts
them, and having each one re-anchor the whole file would have produced a conflict
per PR. This is the sweep, done once at the end.

## Scope

- **Run the acceptance matrix** on a fresh Ubuntu 24.04 host. Two runs:
  1. Root-only mode, **Full install** — all 23 components. Record that
     `vps-boot.sh check` reports `✓` for each and exits 0.
  2. Created-user mode spot check — `install` completes, and the new components
     resolve on `PATH` **as the created user** in a fresh login shell. This is
     where `java`'s and `rust`'s `/etc/profile.d` drop-ins and `uv`'s pinned
     install dir either work or do not.
- **Re-anchor `docs/planning/SPECS.md`**: every `vps-boot.sh:NNN` reference is
  re-derived against the merged file, and the counts and lists are reconciled —
  twelve components becomes twenty-three, five baseline functions becomes six,
  seven parallel arrays becomes eight, the third-party source table gains its new
  rows, the test count becomes 33, and the `Source` row's line count is updated.
  Also refresh `mapped_commit` / `mapped_at` if the mapping fields are still
  meant to describe the file as it now stands.
- **Reconcile `README.md`**: the toolchain table lists all 23 in registry order,
  and any prose stating a count or naming the install modes agrees with the
  script.
- **Reconcile `.claude/CLAUDE.md`**: the component-registry contract, the worked
  example, and the baseline sequence list match the merged code.
- Record any behaviour the runs turn up that contradicts a planning doc as a
  drift record under `docs/epics/epic-1-expand-toolchain-components/drift/`,
  rather than quietly editing SPECS.md to match.
- Fix whatever the runs break, if it is small and local. Anything larger opens
  its own issue rather than growing this PR.

## Out of scope

- New components, new baseline steps, new wizard behaviour. This issue verifies
  and documents; it does not add.
- CI. Nothing runs the suite automatically, including the case this epic added —
  explicitly a follow-up, not this issue.
- Rewriting SPECS.md's prose. Only anchors, counts, lists and demonstrably
  outdated statements change.
- Version pinning or a release process.

## Acceptance criteria / Definition of done

- [ ] `bash tests/test_vps_boot.sh` reports **33 passed, 0 failed**.
- [ ] Fresh Ubuntu 24.04, root-only, Full install: the run completes with no
      failed step, and `vps-boot.sh check` exits **0** with a `✓` for all 23
      components. Paste the check output into the PR body.
- [ ] **No `?` appears anywhere in the check output** — every `check_*` prints a
      real version, `check_claude` included.
- [ ] Created-user run: as the created user, in a fresh login shell,
      `java -version`, `javac -version`, `cargo --version`, `uv --version`,
      `fd --version`, `go version` and the npm-installed CLIs all resolve.
- [ ] The wizard renders correctly at 23 components on an **80×24** terminal —
      picker, collapse summary, and Confirm screen — verified on this build, not
      inherited from issue 08's smaller registry.
- [ ] `check` surfaces unattended-upgrades status and `/var/run/reboot-required`.
- [ ] `check_caddy` reports the UFW state for 80/443 and the run still exits 0.
- [ ] Every `vps-boot.sh:NNN` anchor in `docs/planning/SPECS.md` resolves to the
      construct it claims. Verify each one against the merged file rather than
      adjusting by an offset.
- [ ] The number 23 (and the six group counts) agree across `README.md`,
      `docs/planning/SPECS.md`, `.claude/CLAUDE.md` and the wizard's own computed
      label.
- [ ] `grep -rn 'twelve\|QuickStart' README.md docs/planning/SPECS.md .claude/CLAUDE.md`
      returns nothing stale.

## Relevant files / areas

- `docs/planning/SPECS.md` — anchors in Architecture, Data model & storage,
  Interfaces & integrations, Testing infrastructure, Cross-cutting concerns; plus
  the `Source` and `Tests` rows in the Stack table.
- `README.md:37-52` (toolchain table), `:54` (mode sentence).
- `.claude/CLAUDE.md` — File map, Adding a new component, Conventions.
- `vps-boot.sh`, `tests/test_vps_boot.sh` — the merged state everything is
  re-anchored against.
- `docs/planning/changes/change-1-expand-toolchain-components/13-acceptance-criteria.md`
  and `15-test-host.md`.

## Dependencies

- **Blocked by**: every other issue in this epic (01–08). It is the closing
  sweep and cannot start meaningfully before the registry is complete.
- **Blocks**: nothing.

## PR size note

If this grows past ~1000 changed lines, split it before opening the PR. Expect
well under 150 — most of the work here is running things, not writing them. If the acceptance runs surface real defects, fix only the small local ones
here and open separate issues for the rest.
