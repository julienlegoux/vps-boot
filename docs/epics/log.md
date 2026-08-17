# Log

## 2026-08-17

* **Epic 1 issue 07 completed**: [PR #40](https://github.com/julienlegoux/vps-boot/pull/40)
  merged into `develop`, GitHub issue
  [#25](https://github.com/julienlegoux/vps-boot/issues/25) closed.

* **Epic 1 issue 07 PR opened**:
  [PR #40](https://github.com/julienlegoux/vps-boot/pull/40) against `develop`
  for issue [#25](https://github.com/julienlegoux/vps-boot/issues/25) —
  `caddy` joins the `infra` group before `herdr`: official apt repo install,
  no `ufw allow` call anywhere in `install_caddy`, and `check_caddy` reports
  the service state and, separately, whether UFW allows 80/443 — a closed
  firewall gets a `note` (not a `ko`), so `check` still exits 0 on a
  correctly configured box. No drift recorded. Also reconciled issue 01
  (dependency) to `done`; its issue file and `log.md` had fallen behind
  `issues/index.md`, which already read "done".

* **Epic 1 issue 06 completed**: [PR #38](https://github.com/julienlegoux/vps-boot/pull/38)
  merged into `develop`, GitHub issue
  [#24](https://github.com/julienlegoux/vps-boot/issues/24) closed.

* **Epic 1 issue 04 completed**: [PR #39](https://github.com/julienlegoux/vps-boot/pull/39)
  merged into `develop`, GitHub issue
  [#22](https://github.com/julienlegoux/vps-boot/issues/22) closed.

* **Epic 1 issue 04 PR opened**: [PR #39](https://github.com/julienlegoux/vps-boot/pull/39)
  against `develop` for issue [#22](https://github.com/julienlegoux/vps-boot/issues/22)
  — java, rust and uv join the `languages` and `packaging` groups — java
  probes descending for the newest installable *LTS* `openjdk-NN-jdk-headless`,
  rust installs via `rustup -y --no-modify-path` with pinned
  `RUSTUP_HOME`/`CARGO_HOME`, uv installs with `UV_INSTALL_DIR=/usr/local/bin`.
  Each writes an `/etc/profile.d` drop-in or pins its install dir so it
  resolves for root and a created user alike. Ran alongside issues 03, 05 and
  06. No drift recorded; the fresh-host install/PATH-resolution criteria are
  unverifiable on the Windows dev host, covered instead by a stubbed unit
  test for the LTS probe (never calls apt on a non-LTS major) and grep-based
  structural checks on the rust/uv install flags.

* **Epic 1 issue 06 PR opened**:
  [PR #38](https://github.com/julienlegoux/vps-boot/pull/38) against `develop`
  for issue [#24](https://github.com/julienlegoux/vps-boot/issues/24) —
  populates the `cloud` group with `vercel` and `neon` (npm `-g` installs,
  registered after `node`) and `hostinger` (latest `hostinger/api-cli`
  release resolved from the GitHub API, architecture-matched tarball verified
  against the release's `checksums.sha256` before installing to
  `/usr/local/bin`). `check_hostinger` uses the real `hostinger version`
  subcommand rather than the issue's assumed `--version` flag, which the
  upstream CLI does not define (verified against its `cmd/root.go`). Ran in
  parallel with issues 03–05. No drift recorded; the fresh-Ubuntu smoke test
  and the full `vps-boot.sh check` run are unverifiable on the Windows dev
  host, so the checksum path was proven standalone outside the repo instead.

* **Epic 1 issue 05 completed**: [PR #37](https://github.com/julienlegoux/vps-boot/pull/37)
  merged into `develop`, GitHub issue
  [#23](https://github.com/julienlegoux/vps-boot/issues/23) closed.

* **Epic 1 issue 03 completed**: [PR #36](https://github.com/julienlegoux/vps-boot/pull/36)
  merged into `develop`, GitHub issue
  [#21](https://github.com/julienlegoux/vps-boot/issues/21) closed.

* **Epic 1 issue 05 PR opened**:
  [PR #37](https://github.com/julienlegoux/vps-boot/pull/37) against `develop`
  for issue [#23](https://github.com/julienlegoux/vps-boot/issues/23) —
  `codex`, `gemini` and `pi` join the `agents` group (npm-installed, after
  `opencode` and after `register node`), `pi` deliberately skips its
  documented `pi.dev/install.sh` (interactive PATH prompt would hang
  `step_run`) in favor of its npm package, and `check_claude` gains a real
  version string — it was the only existing check reporting none. Ran
  alongside issues 03, 04 and 06. No drift recorded; the fresh-host
  install/verify criteria are unverifiable on the Windows dev host, covered
  instead by a stubbed unit test for `check_claude` and grep-based structural
  checks (register order, no `pi.dev` reference).

* **Epic 1 issue 01 completed**: [PR #34](https://github.com/julienlegoux/vps-boot/pull/34)
  merged into `develop`, GitHub issue
  [#19](https://github.com/julienlegoux/vps-boot/issues/19) closed. Unblocks
  issues 03–08.

* **Epic 1 issue 02 PR opened**:
  [PR #35](https://github.com/julienlegoux/vps-boot/pull/35) against `develop`
  for issue [#20](https://github.com/julienlegoux/vps-boot/issues/20) —
  `build-essential` joins `bl_update`'s package list, a new mandatory
  `bl_unattended` baseline step installs `unattended-upgrades` and enables the
  security pocket only (`Automatic-Reboot` false), and `do_check` gains an
  unattended-upgrades line plus a `reboot-required` note. Ran in parallel with
  issue 01. No drift recorded; the fresh-host `apt-config dump` /
  `systemctl is-enabled` criteria are unverifiable on the Windows dev host, so
  they're covered by unit tests that stub `apt`/`systemctl`/`chmod` instead.

* **Epic 1 issue 01 PR opened**:
  [PR #34](https://github.com/julienlegoux/vps-boot/pull/34) against `develop`
  for issue [#19](https://github.com/julienlegoux/vps-boot/issues/19) —
  `register()` gains a required `<group>` argument after `<scope>`,
  `COMPONENT_GROUPS` fixes the six group names, and the twelve component blocks
  move verbatim into group order. Unblocks issues 03–08. No drift recorded; the
  `33 passed, 0 failed` criterion is unverifiable on the Windows dev host (10
  root-only cases fail identically before and after the change).

* **Retirement**: Epic 0 (Repair the Epic 1 issue set before implementation)
  retired - 2 issues, milestone 2 closed. Consumed reports
  [2026-08-16-issues-epic-1.md](../reviews/2026-08-16-issues-epic-1.md). Fixed:
  Epic 1's nine issues now carry satisfiable acceptance criteria, resolvable
  `SPECS.md` anchors, a docs-update boundary that keeps issues 03–07 out of each
  other's lines, `size` frontmatter matching their own estimates, and
  `.claude/CLAUDE.md` in the epic's documentation scope. No drift recorded.

* **Epic 0 issue 01 completed**: [PR #31](https://github.com/julienlegoux/vps-boot/pull/31)
  merged, GitHub issue [#29](https://github.com/julienlegoux/vps-boot/issues/29)
  closed.

* **Epic 0 issue 02 completed**: [PR #32](https://github.com/julienlegoux/vps-boot/pull/32)
  merged, GitHub issue [#30](https://github.com/julienlegoux/vps-boot/issues/30)
  closed.

* **Epic 0 issue 02 PR opened**: [PR #32](https://github.com/julienlegoux/vps-boot/pull/32)
  narrows issues 03–07's promise to update `SPECS.md:49-50`'s component roster
  and count down to each issue's own README toolchain row and SPECS.md
  third-party source table row — issue 09 still reconciles the roster and
  count once, at the end. Also adds the re-anchoring deferral bullet to
  issues 02–07, corrects `size: M` to `S` on issues 04 and 06, and drops the
  stale `Target ~500 changed lines` clause from all six. See
  [#30](https://github.com/julienlegoux/vps-boot/issues/30).

* **Epic 0 issue 01 PR opened**: [PR #31](https://github.com/julienlegoux/vps-boot/pull/31)
  repairs issue 08's unsatisfiable `QuickStart` grep and missing `depends_on`
  on issues 03–07, issue 09's phantom `SPECS.md` anchor and stale PR-size
  note, and widens `EPIC_1.md`'s documentation scope to include
  `.claude/CLAUDE.md`. See
  [#29](https://github.com/julienlegoux/vps-boot/issues/29).

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
  See [milestone 2](https://github.com/julienlegoux/vps-boot/milestone/2?closed=1).

## 2026-08-16

* **Epic 0 created**: [Repair the Epic 1 issue set before
  implementation](https://github.com/julienlegoux/vps-boot/issues/28), the
  remediation lane, from
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
