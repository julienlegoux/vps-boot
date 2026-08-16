---
type: Issue
title: "Repair issues 08 and 09 and widen EPIC_1's doc scope"
description: "Fix the two Epic 1 instructions that cannot be followed as written, give issue 08 the dependencies its own acceptance criterion needs, and add .claude/CLAUDE.md to EPIC_1's documentation scope."
tags: [epic-0]
timestamp: 2026-08-17T13:00:00Z
epic: 0
issue: 01
slug: repair-08-09-and-epic-doc-scope
size: S
status: done
gh_issue: 29
gh_pr: 31
depends_on: []
resource: https://github.com/julienlegoux/vps-boot/issues/29
---

# Repair issues 08 and 09 and widen EPIC_1's doc scope

## Summary

Four of the five repairs in Epic 0 land in three files: `EPIC_1.md`, issue 08 and
issue 09. They are the repairs that needed a decision rather than a sweep — which
grep an implementer can actually run, which anchor `SPECS.md` actually holds,
whether `.claude/CLAUDE.md` is documentation the epic authorised, and where issue
08 sits in the build order.

This issue owns those three files completely, including their share of Epic 0's
repair 2 (the re-anchoring deferral bullet, which issue 08 needs too) and repair 3
(the `~500 changed lines` clause, which issue 09 carries while being sized `S`).
Epic 0's other issue owns issues 02–07 and never opens 08, 09 or `EPIC_1.md`, so
the two PRs can run in parallel without touching a shared line.

## Scope

**Issue 08 — the grep that cannot return nothing** (`08:138`).

- Narrow the criterion to
  `grep -rn QuickStart vps-boot.sh tests/ README.md docs/planning/SPECS.md`.
  `docs/planning/SPECS.md:45` ("the wizard's multi-select, QuickStart's defaults")
  is the single line under `docs/` that a correct implementation changes.
- Add a sentence stating that `docs/planning/changes/`, `EPIC_1.md` and the issue
  files under `docs/epics/` keep the old name deliberately — they are the record
  of the decision to rename, not surfaces the rename applies to.

**Issue 08 — the re-anchoring deferral bullet.**

- Add to `08`'s `## Out of scope` the bullet issue 01 already carries at
  `01:76-77`: re-anchoring `SPECS.md`'s line numbers is issue 09's single sweep,
  not this PR's job. Today that fact lives only in `01` and in
  `docs/epics/log.md:12-14`, which an implementer of 08 has no reason to open.

**Issue 08 — its position in the build order** (`08:177-181`).

- Set `depends_on: [1, 3, 4, 5, 6, 7]`.
- Rewrite the `## Dependencies` prose to match: blocked by issue 01 for
  `COMPONENT_GROUP` and by issues 03–07 so the 80×24 criterion
  (`08:143-146`) is verified against the real 23 components rather than against
  whatever the registry happens to hold. Drop the "if this lands first, re-verify
  during issue 09" hedge, which the dependency now makes unnecessary. Issue 09's
  own re-verification criterion (`09:80-82`) stays as it is — it is a second pass
  on the merged build, not a substitute.
- No renumbering follows: issue 08 is already numbered after 03–07, so this makes
  the existing order explicit.

**Issue 09 — an anchor `SPECS.md` does not hold** (`09:27-28`).

- The re-anchoring sweep is illustrated with `vps-boot.sh:396-407`, `:1269-1275`
  and `:1240-1246`. The first two resolve to `SPECS.md:41` and `SPECS.md:57`; the
  third appears nowhere in `SPECS.md` — it is the Confirm-screen range quoted in
  `EPIC_1.md:77`. Replace it with an anchor `SPECS.md` actually contains:
  `vps-boot.sh:385-391` (`SPECS.md:22`) or `vps-boot.sh:766-772` (`SPECS.md:32`).

**Issue 09 — the PR size note** (`09:114`).

- Drop the leading `Target ~500 changed lines;` clause. Issue 09 is `size: S` and
  its own next sentence says "Expect well under 150". Keep the
  "if this grows past ~1000, split it before opening the PR" guard.

**`EPIC_1.md` — the documentation surfaces it names.**

- `EPIC_1.md:88-90` and acceptance criterion 8 (`EPIC_1.md:127`) name only
  `README.md` and `SPECS.md`. Issues 01 and 09 both edit `.claude/CLAUDE.md`
  as well, correctly: issue 01 changes `register()`'s signature and CLAUDE.md's
  "Adding a new component" worked example is the contract documenting it, and
  `docs/planning/CONVENTIONS.md:190-193` makes updating it in the same commit a
  repo rule. The epic under-specified, so the epic is what changes — add
  `.claude/CLAUDE.md` to both places.

**Mirror each edited body to its GitHub issue.**

- The bodies of `#26` (issue 08), `#27` (issue 09) and `#18` (Epic 1) are copies
  of these files with the YAML frontmatter stripped. An implementer reads the
  GitHub issue, so a repair that stops at the `.md` does not reach them. After
  editing, push each body with
  `gh issue edit <n> --body-file <stripped-copy>`.
- Refresh the `timestamp` frontmatter field of each of the three edited files.

## Out of scope

- **Issues 02–07 and `issues/index.md`.** Epic 0's issue 02 owns every one of
  them, including their copies of the deferral bullet and the `~500` clause. Do
  not open them here; the two PRs conflict the moment either crosses that line.
- **Issues 01's own text.** It already carries the deferral bullet and already
  names `.claude/CLAUDE.md`; nothing about it changes.
- **Implementing anything issues 08 or 09 describe.** This edits their text. No
  `vps-boot.sh`, `tests/` or `README.md` change belongs in this PR.
- **Re-reviewing Epic 1.** The findings come from
  `docs/reviews/2026-08-16-issues-epic-1.md` as written.
- **`docs/reviews/2026-08-16-issues-epic-1.md` itself.** It records what the
  issues looked like when they were reviewed.

## Acceptance criteria / Definition of done

- [ ] `grep -n 'grep -rn QuickStart' docs/epics/epic-1-expand-toolchain-components/issues/08-wizard-full-install-and-grid-picker.md`
      shows the command ending in `docs/planning/SPECS.md`, not `docs/`.
- [ ] Running that command from the repo root today returns exactly one line:
      `docs/planning/SPECS.md:45`. (It returns 32 lines with the old `docs/`
      target — that is the defect.)
- [ ] Issue 08 states, in prose, which surfaces keep the `QuickStart` name
      deliberately, naming `docs/planning/changes/`, `EPIC_1.md` and the issue
      files.
- [ ] Issue 08's `## Out of scope` carries a re-anchoring deferral bullet naming
      issue 09.
- [ ] Issue 08's frontmatter reads `depends_on: [1, 3, 4, 5, 6, 7]` and its
      `## Dependencies` section lists the same six issues as blockers.
- [ ] `grep -n '1240-1246' docs/epics/epic-1-expand-toolchain-components/issues/09-verify-and-reanchor-docs.md`
      returns nothing, and every `vps-boot.sh:NNN` range issue 09 cites as an
      example is found in `docs/planning/SPECS.md` by
      `grep -n 'vps-boot.sh:<range>' docs/planning/SPECS.md`.
- [ ] `grep -n 'Target ~500 changed lines' docs/epics/epic-1-expand-toolchain-components/issues/09-verify-and-reanchor-docs.md`
      returns nothing, and the `if this grows past ~1000` guard is still there.
- [ ] `grep -n 'CLAUDE.md' docs/epics/epic-1-expand-toolchain-components/EPIC_1.md`
      hits both the documentation paragraph and acceptance criterion 8.
- [ ] The GitHub bodies of `#18`, `#26` and `#27` match their `.md` files with
      frontmatter stripped — spot-check with
      `gh issue view 26 --json body -q .body | diff - <stripped-copy>`.
- [ ] The `timestamp` of each of the three edited files is refreshed.
- [ ] The PR touches only `EPIC_1.md`, `08-wizard-full-install-and-grid-picker.md`
      and `09-verify-and-reanchor-docs.md`, plus this issue's own status
      bookkeeping.

## Relevant files / areas

- `docs/epics/epic-1-expand-toolchain-components/EPIC_1.md` — `:88-90` (the
  documentation paragraph), `:127` (acceptance criterion 8).
- `docs/epics/epic-1-expand-toolchain-components/issues/08-wizard-full-install-and-grid-picker.md`
  — frontmatter `depends_on`, `:122-131` (`## Out of scope`), `:138` (the grep
  criterion), `:175-181` (`## Dependencies`).
- `docs/epics/epic-1-expand-toolchain-components/issues/09-verify-and-reanchor-docs.md`
  — `:27-30` (the anchor illustration), `:114` (the PR size note).
- `docs/epics/epic-1-expand-toolchain-components/issues/01-registry-groups-and-reorder.md`
  — `:76-77`, the deferral bullet to copy. Read only.
- `docs/planning/SPECS.md` — `:22`, `:32`, `:41`, `:45`, `:57`, the lines every
  anchor above is checked against. Read only.
- `docs/reviews/2026-08-16-issues-epic-1.md` — findings 1, 2, 4 and 5.

## Dependencies

- **Blocked by**: none.
- **Blocks**: nothing. Runs in parallel with Epic 0's issue 02 — their file sets
  are disjoint by construction.

Both must merge before any Epic 1 issue is implemented, which is the whole point
of Epic 0.

## PR size note

Expect well under 100 changed lines across three files; if this grows past ~1000,
split it before opening the PR. It is prose editing — no code, no tests.
