# Issue Review Report

## Scope

- Reviewed: `docs/epics/epic-1-expand-toolchain-components/issues/01-…` through
  `09-…`, plus `issues/index.md`; `docs/epics/index.md` and `docs/epics/log.md`
  read for cross-references.
- Reviewed against: `docs/epics/epic-1-expand-toolchain-components/EPIC_1.md`,
  with `docs/planning/SPECS.md`, `docs/planning/CONVENTIONS.md`, `.claude/CLAUDE.md`
  and the change ledger under
  `docs/planning/changes/change-1-expand-toolchain-components/` consulted for the
  standards and rationale the issues cite. Every `vps-boot.sh:NNN`,
  `tests/test_vps_boot.sh:NNN` and `README.md:NNN` anchor was resolved against the
  working tree at `89fcc9f`.
- GitHub verification: verified — `#19`–`#27` all exist, all `OPEN`, all on
  milestone 1, all nine attached as native sub-issues of the epic's tracking issue
  `#18`, titles byte-identical to each file's `title:` frontmatter, and every
  `resource:` URL points at its own number. All nine carry the `enhancement`
  label; `#18` carries `epic`.
- External review: standard — openai-codex/gpt-5.6-terra.

## Findings

### P2 — Issue 08's stale-term check cannot pass without rewriting the decision records

- Location: `docs/epics/epic-1-expand-toolchain-components/issues/08-wizard-full-install-and-grid-picker.md:138`
- Source: `EPIC_1.md:64` ("`QuickStart` becomes `Full install`"); the same term on
  17 lines across `docs/planning/changes/change-1-expand-toolchain-components/`
  (`01-approach.md`, `06-shell-essentials.md`, `08-additional-agent-clis.md`,
  `10-defaults-and-run-order.md`, `13-acceptance-criteria.md`,
  `14-quickstart-scope.md`, `15-test-host.md`, `index.md`) and on
  `docs/planning/log.md:40`.
- Problem: the acceptance criterion is
  `grep -rn QuickStart vps-boot.sh tests/ README.md docs/` returns nothing. It
  cannot: `docs/` holds the epic that records the rename, the change ledger that
  decided it, and issue 08 itself (which names the old term on seven lines — `:4`,
  `:44`, `:113`, `:115`, `:117`, `:118`, `:138`). Of the 28 `docs/` lines carrying
  the term today, exactly one — `docs/planning/SPECS.md:45` — should change; the
  other 27 survive a correct implementation.
- Impact: the implementer either cannot tick the box, or ticks it by deleting
  history from the ledger — decision records whose whole value is that they say
  what was decided and why. The ledger is also what issue 08's own "Relevant
  files" sends them to read (`14-quickstart-scope.md`).
- Recommendation: narrow the grep to the surfaces that must actually change —
  `grep -rn QuickStart vps-boot.sh tests/ README.md docs/planning/SPECS.md` — and
  state that `docs/planning/changes/`, `EPIC_1.md` and the issue files keep the
  old name deliberately.

### P2 — The docs-update boundary is stated in issue 01 only, while six issues edit the same lines

- Location: `issues/01-registry-groups-and-reorder.md:76-77` (the only statement of
  the boundary); `issues/03-tools-component.md:47-48`,
  `04-java-rust-uv-components.md:73-74`, `05-agent-cli-components.md:59-61`,
  `06-cloud-cli-components.md:54-57`, `07-caddy-component.md:48-50` (each
  promising the same edits); `issues/09-verify-and-reanchor-docs.md:41-47` (the
  sweep).
- Source: `EPIC_1.md:127` — acceptance criterion 8, "`README.md` and `SPECS.md`
  are updated in the same commit as the code"; `docs/epics/log.md:12-14`, where the
  deferral is actually recorded.
- Problem: issues 03–07 all carry `depends_on: [1]` and none blocks another, so
  they are explicitly parallel-workable — and each one is told to "update the
  component list and count in `docs/planning/SPECS.md`" and add a row to
  `README.md:37-52`. `SPECS.md:49` is a single sentence enumerating twelve
  components in run order; five PRs each rewriting it conflict by construction.
  Separately, only issue 01 says that SPECS.md's line anchors are issue 09's job.
  An implementer on issue 04 or 06 reads epic AC 8 and has no signal not to
  re-anchor; the note that says otherwise lives in `docs/epics/log.md`, which is
  not a file an implementer opens.
- Impact: a merge conflict on the same two regions in every PR after the first,
  and anchor work that is either duplicated across five PRs or done twice and
  undone. Both are avoidable and neither is anybody's stated responsibility.
- Recommendation: repeat issue 01's deferral bullet verbatim in the "Out of scope"
  of issues 02–08 ("re-anchoring SPECS.md's line numbers — issue 09 sweeps"), and
  make the split explicit: 03–07 add their **third-party source table row** and
  their **README toolchain row** only, while the component list and count at
  `SPECS.md:49` are reconciled once, in issue 09. Issue 09 already owns that
  reconciliation (`09:41-47`), so this narrows the per-issue promise rather than
  moving work.

### P3 — `size: M` on issues 04 and 06 contradicts those issues' own estimates

- Location: `issues/04-java-rust-uv-components.md:10` and `:132`;
  `issues/06-cloud-cli-components.md:10` and `:110`.
- Source: `pipeline-interfaces.md` issue schema — "S ≈ under 200 changed lines,
  M ≈ 200–500, L ≈ 500–1000".
- Problem: issue 04 is labelled `size: M` and estimates "Expect ~150"; issue 06 is
  `size: M` and estimates "Expect ~130". Both are S by the contract's own
  thresholds. Conversely, all nine issues open their PR size note with the same
  boilerplate "Target ~500 changed lines", which reads as a target of 500 on five
  issues labelled `size: S` and estimating 60–150.
- Impact: the frontmatter is the field a scheduler or a reader sorts on, and it
  disagrees with the prose two paragraphs down. Nothing breaks, but the label
  stops being informative.
- Recommendation: set issues 04 and 06 to `size: S`, and drop the "~500" clause
  from the boilerplate on the S issues, leaving the "if this grows past ~1000,
  split it" guard.

### P3 — Issue 09 cites a SPECS.md anchor that SPECS.md does not contain

- Location: `issues/09-verify-and-reanchor-docs.md:27-29`.
- Source: `docs/planning/SPECS.md` carries nine `vps-boot.sh:NNN` references
  (`:22`, `:32`, `:41`, `:57`, `:65`, `:80`, `:93`, `:249`, `:255`) and twenty-one
  line anchors in total.
- Problem: issue 09 illustrates the sweep with "`vps-boot.sh:396-407`,
  `:1269-1275`, `:1240-1246` and a dozen more". The first two resolve
  (`SPECS.md:41` and `:57`); `1240-1246` does not appear in SPECS.md at all — it is
  the Confirm-screen range from `EPIC_1.md:77`.
- Impact: minor, but the implementer's first act on this issue is to go looking
  for the anchors named, and one of the three is not there.
- Recommendation: replace `:1240-1246` with an anchor SPECS.md actually holds —
  `vps-boot.sh:385-391` (`SPECS.md:22`) or `:766-772` (`SPECS.md:32`).

### P3 — `.claude/CLAUDE.md` is issue scope the epic never names

- Location: `issues/01-registry-groups-and-reorder.md:64-65` and `:93-94`;
  `issues/09-verify-and-reanchor-docs.md:51-52`.
- Source: `EPIC_1.md:88-90` ("Documentation, in the same commit as the code" —
  README's toolchain table and SPECS.md only) and `EPIC_1.md:127` (AC 8, same two
  files).
- Problem: both issues add `.claude/CLAUDE.md` to their scope and acceptance
  criteria without flagging it as an assumption. It is plainly the right call —
  issue 01 changes `register()`'s signature and CLAUDE.md's "Adding a new
  component" worked example is the contract that documents it, so leaving it
  unedited ships a wrong example — but the epic does not authorise it.
- Impact: none to the build; it costs traceability. Anyone diffing epic against
  issues sees unexplained extra scope and has to re-derive why it belongs.
- Recommendation: one line in each issue naming it as a necessary consequence of
  the `register` signature change, or add `.claude/CLAUDE.md` to the epic's
  documentation bullet.

## Coverage notes

- **Epic coverage is complete.** All eleven new components are placed: `tools`
  (03), `java`/`rust`/`uv` (04), `codex`/`gemini`/`pi` (05),
  `vercel`/`hostinger`/`neon` (06), `caddy` (07). All six `COMPONENT_GROUP` values
  are populated and the per-group counts sum to the epic's 23 (core 4, languages 5,
  packaging 3, agents 6, cloud 3, infra 2). Both baseline changes are in 02, the
  wizard rework in 08, the registry-invariant test in 01, the `check_claude` fix in
  05. Every one of the epic's eight acceptance criteria has a named owner, and
  issue 09 independently re-verifies criteria 2–7 at the real 23 components.
- **Ordering is sound and the frontmatter agrees with the prose.** Issue 01 is the
  only gate; 03–08 depend on it for `register`'s new argument; 02 correctly claims
  no dependency (it touches only `bl_*` and `do_check`); 09 depends on all eight.
  Every issue's `## Dependencies` section matches its `depends_on:`. Issue 01's
  claim that the group order preserves the positional `node`-before-npm constraint
  for free checks out against the target order it specifies.
- **The line anchors are unusually accurate.** Every anchor sampled resolves to
  the construct claimed, several of them exactly: `vps-boot.sh:766-772` is
  `bl_update`, `:1269-1275` is the hardcoded baseline sequence, `:333` is the blind
  `printf '\033[%dA'`, `:1204` is the five-tools-twelve-installed mode label,
  `:1469-1481` is the sign-in footer, `:1111-1114` is `component_is_applicable`,
  `:571-577` is the version-less `check_claude`, `:631` is the `update-alternatives`
  idiom issue 03 borrows. On the test side, `tests/test_vps_boot.sh:148`, `:230`
  and `:255` are the three `value=QuickStart` stubs; `:610` is the README
  assertion; `:635` is the run_test label; `README.md:29-35`, `:37-52` and `:54`
  are the two tables and the mode sentence. The **32** existing `run_test` cases
  are confirmed by count, so the 33 the issues assert is right.
- **Conventions are reflected, not guessed at.** `apt` never `apt-get`
  (`CONVENTIONS.md:58`) is cited in issue 03; `note` rather than `ko` for a
  deliberately-closed firewall and a pending reboot (`CONVENTIONS.md:144`) is cited
  and correctly applied in issues 02 and 07; the UI helper vocabulary, `/dev/tty`
  reads, and the `install_x`/`check_x`/`register x` triple all hold. Issue 08
  explicitly preserves `prompt_multiselect`'s calling contract and glyph set.
- **The epic's "Two fixes from the version audit" heading (`EPIC_1.md:82`) is loose,
  and the issues resolved it correctly.** The ledger
  (`20-version-audit.md:52-60`) records two *findings*, of which only one — the
  missing `check_claude` version — is a fix; the second was the Node floor
  investigation, closed with "no guard". Issue 05 implements the one fix and puts
  the Node guard out of scope with the reasoning. No coverage is missing here.
- **Issue 09's drift instruction is contract-conformant, not invented scope.** The
  external pass flagged `09:53-55` (record contradictions as a drift record under
  the epic's `drift/`) as an artifact the epic never asks for; it is in fact what
  `pipeline-interfaces.md` mandates for exactly this situation, and it is the
  correct alternative to quietly editing SPECS.md. Its neighbour, "fix whatever the
  runs break, if it is small and local" (`09:56-57`), is bounded in the same
  sentence by "Anything larger opens its own issue".
- **Out-of-scope sections track the epic** across all nine issues: no
  `COMPONENT_REQUIRES`, no CI, no version pinning, no Node guard, no credential
  provisioning, no `ufw allow` in `install_caddy`, no wizard work beyond the picker
  and the two summary surfaces. Issue 03 goes further and pre-empts the obvious
  mistake ("if issue 02 has not merged yet, do not compensate by adding
  `build-essential` here").
- **`issues/index.md` conforms**: no frontmatter (correct for a non-root index),
  one mechanical bullet per issue carrying size, status and the GitHub link, all
  nine present and in order. The `./`-prefixed relative links are a cosmetic
  variance from the bullet spec's bare `file.md`, resolving identically; not
  reported as a finding.

## Open questions

- Issue 08 lands the picker rewrite against whatever the registry holds at merge
  time, and says so honestly (`08:178-181`), deferring the real 80×24 check to
  issue 09. Working it *after* 03–07 rather than in numeric position would let it
  verify its own acceptance criterion, at the cost of a rebase against five merged
  PRs. The issues leave this to the implementer; it may be worth deciding once, up
  front.

---

`triage-reports` is what turns these findings into work: it reads every report
under `docs/reviews/`, groups findings by the repair that resolves them, and
converts what you accept into a remediation epic. Nothing here has been repaired —
a review is read-only.
