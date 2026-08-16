# Log

## 2026-08-17

* **Epic 0 issues created**: two issues, `#29`–`#30`, both on milestone 2 and
  attached as native sub-issues of `#28`. Split by **file ownership** rather than
  by repair: repairs 2 and 3 both span Epic 1's issues 02–08, so a per-repair
  split would have put two PRs in issue 08 at once. Issue 01
  ([#29](https://github.com/julienlegoux/vps-boot/issues/29)) owns `EPIC_1.md`,
  issue 08 and issue 09 — the grep that cannot return nothing, the phantom
  `SPECS.md` anchor, `.claude/CLAUDE.md` in the epic's doc scope, and 08's
  `depends_on` on 03–07. Issue 02
  ([#30](https://github.com/julienlegoux/vps-boot/issues/30)) owns issues 02–07
  and `issues/index.md` — the narrowed docs promise, the deferral bullet, and the
  `size` corrections. The two file sets are disjoint, so neither blocks the other.
  Both add mirroring the edited bodies to their GitHub issues
  (`gh issue edit <n> --body-file …`), which the epic did not call out: an
  implementer reads `#19`–`#27`, not the `.md`, so a repair that stops at disk
  never reaches them.
  See [issues/index.md](epic-0-issue-set-repairs/issues/index.md).

## 2026-08-16

* **Epic 0 created**: [Repair the Epic 1 issue set before
  implementation](epic-0-issue-set-repairs/EPIC_0.md), the remediation lane, from
  [the issue review report](../reviews/2026-08-16-issues-epic-1.md) — the one
  report consumed by this triage. Five findings extracted, none dropped as stale,
  none recorded as `won't-fix`, grouped into five repairs: issue 08's
  unsatisfiable `QuickStart` grep and issue 09's phantom `SPECS.md` anchor; the
  docs-update boundary repeated across issues 02–08 so five parallel PRs stop
  rewriting `SPECS.md:49`; `size:` frontmatter on 04 and 06; `.claude/CLAUDE.md`
  added to `EPIC_1.md`'s documentation scope; and issue 08 wired to depend on
  03–07 so it verifies its own 80×24 criterion. No lint reports and no legacy
  `docs/REPORT_<n>.md` exist in this repo. Tracking issue
  [#28](https://github.com/julienlegoux/vps-boot/issues/28) on milestone 2. Epic
  1's implementation waits on this.

* **Epic 1 issues created**: nine issues, `#19`–`#27`, all on milestone 1 and
  attached as native sub-issues of `#18`. Issue 01
  ([#19](https://github.com/julienlegoux/vps-boot/issues/19)) is the gate — it
  adds `COMPONENT_GROUP` and reorders the registry — and 03–08 depend on it; 02
  ([#20](https://github.com/julienlegoux/vps-boot/issues/20)) touches only the
  baseline and runs in parallel; 09
  ([#27](https://github.com/julienlegoux/vps-boot/issues/27)) is the closing
  sweep and depends on all eight. Per-issue docs updates ride in each PR (epic
  AC 8); only the SPECS.md line-anchor re-derivation is deferred to 09, since
  every PR shifts them.
  See [issues/index.md](epic-1-expand-toolchain-components/issues/index.md).

* **Epic 1 updated** after
  [decision 05](../planning/changes/change-1-expand-toolchain-components/05-java-jdk.md)
  was reopened: the `java` component probes for the newest installable **LTS**
  JDK (LTS majors only, `(n - 21) % 4 == 0`) rather than the newest JDK of any
  kind, which could have selected a six-month feature release. Scope table and
  Notes regenerated; issue #18 body updated; `gh_issue` and `milestone`
  unchanged.

* **Bundle established**: `docs/epics/` created by `define-change`.
* **Epic 1 created**: [Expand the toolchain component
  registry](epic-1-expand-toolchain-components/EPIC_1.md), from
  [change 1](../planning/changes/change-1-expand-toolchain-components/index.md)
  (20 decisions, all decided). Takes `vps-boot.sh` from twelve components to
  twenty-three, adds two baseline steps, and rebuilds the component picker.
