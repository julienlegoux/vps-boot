---
type: Epic
title: "Repair the Epic 1 issue set before implementation"
description: "Fix the acceptance criteria, scope boundaries and metadata that the Epic 1 issue review found, so the nine issues can be implemented in their stated order and parallelism without conflicting on the same documentation lines."
tags: [epic, remediation]
timestamp: 2026-08-16T20:34:00Z
epic: 0
slug: issue-set-repairs
status: open
gh_issue: 28
milestone: 2
resource: https://github.com/julienlegoux/vps-boot/issues/28
source: docs/reviews/2026-08-16-issues-epic-1.md
---

# Epic 0: Repair the Epic 1 issue set before implementation

## Goal

Epic 1's nine issues can be implemented in the order they are numbered, in
parallel where they claim to be parallel, without two PRs rewriting the same
`SPECS.md` sentence and without an acceptance criterion that can only be ticked
by deleting decision records.

None of Epic 1's issues has been implemented yet — `#19`–`#27` are all open. Every
repair below therefore lands in the plan, before the code it would otherwise
misdirect, which is what makes this epic 0 rather than a follow-up.

## Scope

All five repairs edit planning artifacts under
`docs/epics/epic-1-expand-toolchain-components/`. There is no code work: the
report series holds one `review-issues` report and no `review-implementation`
report, so nothing here grades shipped code.

**1. Instructions that cannot be followed as written.**

Issue 08's acceptance criterion is
`grep -rn QuickStart vps-boot.sh tests/ README.md docs/` returns nothing. It
cannot: 32 lines under `docs/` carry the term today, and exactly one —
`docs/planning/SPECS.md:45` — should change. The other 31 are the change ledger
that decided the rename, `EPIC_1.md` which records it, and issue 08 itself.
Narrow the grep to `vps-boot.sh tests/ README.md docs/planning/SPECS.md`, and
state in the issue that `docs/planning/changes/`, `EPIC_1.md` and the issue files
keep the old name deliberately.

Issue 09 illustrates its re-anchoring sweep with `vps-boot.sh:396-407`,
`:1269-1275` and `:1240-1246`. The first two resolve to `SPECS.md:41` and `:57`;
the third appears nowhere in `SPECS.md` — it is the Confirm-screen range from
`EPIC_1.md:77`. Replace it with an anchor `SPECS.md` actually holds:
`vps-boot.sh:385-391` (`SPECS.md:22`) or `:766-772` (`SPECS.md:32`).

**2. The docs-update boundary, stated once and needed seven times.**

Issues 03–07 all carry `depends_on: [1]`, none blocks another, and each promises
to "update the component list and count in `docs/planning/SPECS.md`".
`SPECS.md:49` is a single sentence enumerating the components in run order — five
PRs each rewriting it conflict by construction. Separately, only issue 01 records
that re-anchoring `SPECS.md`'s line numbers is issue 09's job; the note that says
so otherwise lives in `docs/epics/log.md:12-14`, which is not a file an
implementer opens.

Repeat issue 01's deferral bullet in the `## Out of scope` of issues 02–08, and
narrow issues 03–07 to their **third-party source table row** and their
**README toolchain row** only. The component list and count at `SPECS.md:49` are
reconciled once, in issue 09, which already owns that reconciliation
(`09:41-47`). This narrows the per-issue promise rather than moving work.

**3. `size` frontmatter that contradicts the issues' own estimates.**

Issue 04 is `size: M` and estimates ~150 changed lines; issue 06 is `size: M` and
estimates ~130. Both are `S` by the bands in `pipeline-interfaces.md`. Set them
to `S`. All nine issues also open their PR size note with "Target ~500 changed
lines", which reads as a target of 500 on issues labelled `S` and estimating
60–150; drop that clause from the `S` issues and keep the "if this grows past
~1000, split it" guard.

**4. `.claude/CLAUDE.md` as documentation scope the epic never authorised.**

Issues 01 and 09 add `.claude/CLAUDE.md` to their scope and acceptance criteria.
That is the right call — issue 01 changes `register()`'s signature and CLAUDE.md's
"Adding a new component" worked example is the contract documenting it, so
leaving it unedited ships a wrong example — but `EPIC_1.md:88-90` and acceptance
criterion 8 (`EPIC_1.md:127`) name only `README.md` and `SPECS.md`. The epic
under-specified, so the epic is what changes: add `.claude/CLAUDE.md` to both.

**5. Issue 08's position in the build order, decided rather than deferred.**

Issue 08 rewrites the picker against whatever the registry holds at merge time
and says so honestly (`08:178-181`), deferring the real 80×24 check to issue 09.
Give it `depends_on` covering 03–07 so it verifies its own acceptance criterion
against the real 23 components. Issue 08 is already numbered after 03–07, so this
makes the existing numbering explicit and no renumbering follows. Its
`## Dependencies` section is updated to match.

## Out of scope

- **Implementing any of Epic 1's issues.** This epic repairs their text; the work
  they describe stays theirs.
- **Re-reviewing Epic 1.** Severities and findings come from the report as
  written. A finding believed wrong would be a `won't-fix` recorded here, not a
  re-grade — and none was.
- **The `./`-prefixed relative links in `issues/index.md`.** The review saw them,
  judged them a cosmetic variance that resolves identically, and did not report
  them as a finding.
- **Editing `docs/reviews/2026-08-16-issues-epic-1.md`.** The report is the record
  of what the issues looked like when someone looked at them.

## Acceptance criteria

1. `grep -rn QuickStart vps-boot.sh tests/ README.md docs/planning/SPECS.md`
   returns only lines a correct Epic 1 implementation changes, and issue 08's
   criterion is that command — with a sentence naming the surfaces that keep the
   old term deliberately.
2. Every `docs/planning/SPECS.md` anchor cited across issues 01–09 resolves to a
   line `SPECS.md` actually contains.
3. No issue among 03–07 promises to edit the component list or count at
   `SPECS.md:49`; issue 09 alone does.
4. Every issue among 02–08 carries the re-anchoring deferral bullet in its
   `## Out of scope`.
5. Each issue's `size:` frontmatter agrees with its own estimate against the
   S/M/L bands in `pipeline-interfaces.md`, and no issue labelled `S` carries a
   "~500 changed lines" target.
6. `EPIC_1.md` and issues 01 and 09 name the same set of documentation files,
   `.claude/CLAUDE.md` included.
7. Issue 08's `depends_on` covers 03–07 and its `## Dependencies` section says the
   same thing in prose.

## Dependencies

None. This epic precedes Epic 1's implementation and is the reason its issues can
be trusted.

## Context

- [Epic 1](/epic-1-expand-toolchain-components/EPIC_1.md) — the epic whose issue
  set is repaired here
- [Issue review report](../../reviews/2026-08-16-issues-epic-1.md) — the five
  findings, with both sides of each cited
- [Technical specs](../../planning/SPECS.md)
- [Conventions](../../planning/CONVENTIONS.md)

## Notes

**Reports consumed.** One: `docs/reviews/2026-08-16-issues-epic-1.md`
(`review-issues`, 2026-08-16, two P2 and three P3 findings). No lint reports and
no legacy `docs/REPORT_<n>.md` files exist in this repo. No report in the series
had been consumed by a previous triage.

**Nothing was dropped as stale.** All five findings were verified against the
working tree at `8f49c8e`: every cited line still says what the report quotes,
`git log 89fcc9f..HEAD -- docs/` is empty, no open or closed GitHub issue covers
any of them, and `docs/planning/DRIFT.md` does not exist, so nothing had been
accepted as drift.

**No won't-fix decisions.** All five findings were accepted as work.

**The ordering question was decided, not deferred.** The report left open whether
issue 08 should be worked after 03–07 rather than in numeric position; repair 5
answers it. The cost is a rebase against five merged PRs, and it is small: 03–07
add `install_`/`check_`/`register` blocks in the Components section, while 08
rewrites `prompt_multiselect` and the two summary surfaces — different regions of
the file.

**Two of the five repairs are P3 metadata.** They are here because a `size:` field
that disagrees with the prose two paragraphs down and an unexplained scope
addition both cost a reader time on every pass, and both are one-line fixes while
the issues are already open on the bench.

**This epic is temporary.** Epic 0 is the remediation slot, not a permanent
fixture; `close-epic` retires it — folder and all — once every issue is `done` and
its milestone is closed, leaving the retirement notice in `docs/epics/log.md`.
