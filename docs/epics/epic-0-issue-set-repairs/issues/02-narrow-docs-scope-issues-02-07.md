---
type: Issue
title: "Narrow the docs promise and fix the sizes in issues 02–07"
description: "Stop issues 03–07 promising to rewrite the same SPECS.md sentence, give issues 02–07 the re-anchoring deferral bullet, and reconcile the size frontmatter with each issue's own estimate."
tags: [epic-0]
timestamp: 2026-08-17T11:00:00Z
epic: 0
issue: 02
slug: narrow-docs-scope-issues-02-07
size: S
status: in-progress
gh_issue: 30
depends_on: []
resource: https://github.com/julienlegoux/vps-boot/issues/30
---

# Narrow the docs promise and fix the sizes in issues 02–07

## Summary

Issues 03–07 of Epic 1 all carry `depends_on: [1]`, none blocks another, and each
promises to update "the component list and count in `docs/planning/SPECS.md`".
That list is a single sentence — `docs/planning/SPECS.md:49-50`, "Twelve
components are registered, in run order: …" — so five PRs that are explicitly
allowed to run in parallel would each rewrite the same two lines. They conflict by
construction.

Issue 09 already owns reconciling that list and count once, at the end
(`09:41-47`, `09:88-90`). This issue narrows the per-issue promise to what each PR
can own alone — its **third-party source table row** and its **README toolchain
row** — rather than moving any work. It also carries repair 2's deferral bullet
into issues 02–07 and repair 3's `size` corrections, both of which touch the same
six files.

Epic 0's issue 01 owns `EPIC_1.md`, issue 08 and issue 09 and never opens these
six, so the two PRs can run in parallel without touching a shared line.

## Scope

**Narrow the docs promise in issues 03–07.**

For each of `03`, `04`, `05`, `06`, `07`, in both the scope prose and the
acceptance criteria:

- Keep: the row in `README.md`'s toolchain table (`README.md:37-52`) and the row
  (or rows) in `SPECS.md`'s third-party source table under Interfaces.
- Remove: any promise to update the component **list** or **count** in
  `SPECS.md`. State that `SPECS.md:49-50` is reconciled once, in issue 09, so five
  parallel PRs do not rewrite the same sentence.
- The current wordings to edit are `03:47-48`, `04:73-74`, `05:59-61`, `06:54-57`,
  `07:48-50`, plus the matching
  `- [ ] README.md and docs/planning/SPECS.md updated in the same commit.`
  criteria at `03:74`, `04:106`, `05:91`, `06:89`, `07:76` and the
  `## Relevant files / areas` entries at `03:84-85`, `04:119`, `05:99`, `06:98`,
  `07:87`.
- Issue 06's note that `hostinger` joins `go` and `herdr` as a non-apt, non-npm
  source, and issue 05's note that the npm row goes from four packages to seven,
  are third-party-source-table facts — they stay.

**Add the re-anchoring deferral bullet to issues 02–07.**

- Copy the bullet issue 01 carries at `01:76-77` into each `## Out of scope`:
  re-anchoring `SPECS.md`'s line numbers past the insertion points is issue 09's
  single sweep. Today that fact lives only in `01` and in `docs/epics/log.md:12-14`,
  which no implementer opens.
- Issue 02 gets this bullet but **not** the narrowing above: it documents the
  baseline going from five functions to six (`02:52-55`), which is a different
  part of `SPECS.md` and conflicts with nobody.

**Reconcile `size` with each issue's own estimate.**

- Issue 04 is `size: M` and its PR size note estimates ~150 changed lines; issue
  06 is `size: M` and estimates ~130. Both are `S` by the bands in
  `../_shared/pipeline-interfaces.md` (S ≈ under 200, M ≈ 200–500). Set both to
  `size: S`.
- Every one of `02`–`07` opens its PR size note with `Target ~500 changed lines;`
  while being sized `S` and estimating 60–150. Drop that clause from all six; keep
  the "if this grows past ~1000, split it before opening the PR" guard.

**Keep the index and GitHub in sync.**

- Update the `size` shown for issues 04 and 06 in
  `docs/epics/epic-1-expand-toolchain-components/issues/index.md`.
- The GitHub bodies of `#20`–`#25` are copies of these files with the YAML
  frontmatter stripped. An implementer reads the GitHub issue, so push each edited
  body with `gh issue edit <n> --body-file <stripped-copy>`:
  `02`→`#20`, `03`→`#21`, `04`→`#22`, `05`→`#23`, `06`→`#24`, `07`→`#25`.
- Refresh the `timestamp` frontmatter field of each edited file.

## Out of scope

- **`EPIC_1.md`, issue 08 and issue 09.** Epic 0's issue 01 owns all three,
  including issue 08's copy of the deferral bullet and issue 09's `~500` clause.
  Do not open them here.
- **Moving work between Epic 1 issues.** The component list and count were already
  issue 09's to reconcile; this narrows a promise five issues should not have
  made, and adds nothing to 09.
- **Issue 01's text**, which already carries the deferral bullet, and issues 01
  and 08, which are `size: M` with estimates (~200, ~250) that agree — their
  `Target ~500 changed lines` clause stays.
- **Implementing anything issues 02–07 describe.** No `vps-boot.sh`, `tests/` or
  `README.md` change belongs in this PR.
- **The `./`-prefixed relative links in `issues/index.md`.** The review saw them
  and did not report them.

## Acceptance criteria / Definition of done

- [ ] `grep -rn 'component list\|list, count' docs/epics/epic-1-expand-toolchain-components/issues/0[34567]-*.md`
      returns nothing (it returns six lines today: `03:48`, `03:84`, `04:74`,
      `05:60`, `06:55`, `07:49`), while `09:41-47` still holds the single
      reconciliation.
- [ ] Each of issues 03–07 names its `README.md` toolchain row and its
      `SPECS.md` third-party source table row, and says the component list and
      count at `SPECS.md:49-50` are issue 09's.
- [ ] `grep -c 'issue 09' docs/epics/epic-1-expand-toolchain-components/issues/0[234567]-*.md`
      reports at least one hit per file — the deferral bullet.
- [ ] `grep -n '^size:' docs/epics/epic-1-expand-toolchain-components/issues/0[234567]-*.md`
      reports `S` for all six.
- [ ] `grep -rn 'Target ~500 changed lines' docs/epics/epic-1-expand-toolchain-components/issues/`
      hits only `01-registry-groups-and-reorder.md` and
      `08-wizard-full-install-and-grid-picker.md`, the two `M` issues. (If Epic 0's
      issue 01 has already merged, `09` is gone from that list too; if it has not,
      `09` still appears and is not this PR's to fix.)
- [ ] `issues/index.md` shows `S` for issues 04 and 06.
- [ ] The GitHub bodies of `#20`–`#25` match their `.md` files with frontmatter
      stripped — spot-check with
      `gh issue view 22 --json body -q .body | diff - <stripped-copy>`.
- [ ] The `timestamp` of each edited file is refreshed.
- [ ] The PR touches only `02-…` through `07-…` and `issues/index.md`, plus this
      issue's own status bookkeeping.

## Relevant files / areas

- `docs/epics/epic-1-expand-toolchain-components/issues/02-baseline-build-essential-auto-updates.md`
  — `## Out of scope` (bullet), `:105` (PR size note).
- `.../issues/03-tools-component.md` — `:47-48`, `:74`, `:84-85`, `:94`.
- `.../issues/04-java-rust-uv-components.md` — frontmatter `size`, `:73-74`,
  `:106`, `:119`, `:131`.
- `.../issues/05-agent-cli-components.md` — `:59-61`, `:91`, `:99`, `:110`.
- `.../issues/06-cloud-cli-components.md` — frontmatter `size`, `:54-57`, `:89`,
  `:98`, `:109`.
- `.../issues/07-caddy-component.md` — `:48-50`, `:76`, `:87`, `:97`.
- `.../issues/index.md` — the `size` shown per bullet.
- `.../issues/01-registry-groups-and-reorder.md` — `:76-77`, the deferral bullet
  to copy. Read only.
- `.../issues/09-verify-and-reanchor-docs.md` — `:41-47`, `:88-90`, the
  reconciliation this narrowing relies on. Read only.
- `docs/planning/SPECS.md:49-50` — the single sentence five PRs would have
  rewritten. Read only.
- `docs/reviews/2026-08-16-issues-epic-1.md` — findings 2 and 3.

## Dependencies

- **Blocked by**: none.
- **Blocks**: nothing. Runs in parallel with Epic 0's issue 01 — their file sets
  are disjoint by construction.

Both must merge before any Epic 1 issue is implemented, which is the whole point
of Epic 0.

## PR size note

Expect roughly 100 changed lines across seven files; if this grows past ~1000,
split it before opening the PR. It is prose editing repeated six times — no code,
no tests.
