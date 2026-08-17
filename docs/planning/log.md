# Log

## 2026-08-17

* **Drift register established** at [DRIFT.md](DRIFT.md), promoted from Epic 1's
  two drift records at epic close. Both come from issue 09's acceptance runs and
  have distinct causes, so they stay two entries. (1) *Root-only Full install
  offers 22 of the 23 registered components* — `component_is_applicable` filters
  `sudo_nopasswd` out when there is no non-root user to name it in, so the epic's
  "all 23" criterion is 22 in that mode; **accepted**, with SPECS.md and README.md
  already restated to give both numbers instead of one that is wrong in one mode.
  (2) *The documented user-scope idiom starts in a directory the user cannot
  read* — `sudo -u "$USERNAME" -H bash` sets `HOME` but inherits root's `/root`
  (mode 700), and the created-user run died at Hermes on uv probing `.`;
  **resolved (2026-08-17)**, the idiom now carries a mandatory `cd "$HOME"` in
  both CLAUDE.md and SPECS.md and is asserted by the suite via
  `hermes_user_script`. Neither disposition leaves open work; both revisit
  triggers are structural (a second mode-dependent component, a second
  `user`-scope component).

## 2026-08-16 — change 1, decision 05 reopened

* **[Decision 05 (Java)](/changes/change-1-expand-toolchain-components/05-java-jdk.md)
  reopened and re-decided** after the epic was written. The accepted verdict —
  probe for the newest installable `openjdk-NN-jdk-headless` — had no notion of
  LTS. It resolves correctly to 25 on noble today, but only because Ubuntu has
  backported *only* LTS JDKs there (`17`, `21`, `25` present; `22`, `23`, `24`,
  `26` absent): the right answer by accident, resting on a policy this project
  does not control. New verdict restricts the probe to LTS majors via
  `(n - 21) % 4 == 0` (17/21/25/29/33), which needs no bump in 2027.
* **Root cause worth remembering**: for Java, "distro default", "newest" and
  "newest LTS" are three different versions — 21, 25 and 25 today. For `go` and
  `python`, whose probing idiom was borrowed, they collapse into one. That is
  why the idiom transplanted badly and needed two corrections. Both superseded
  verdicts are kept as history in the decision doc.
* **Propagated** to `EPIC_1.md` (scope table + Notes) and to
  [issue #18](https://github.com/julienlegoux/vps-boot/issues/18);
  `gh_issue`/`milestone` untouched.

## 2026-08-16 — change 1

* **Change ledger opened**: [change
  1](/changes/change-1-expand-toolchain-components/index.md), brownfield
  planning for expanding the component registry. 20 decisions, all decided;
  delivered as [Epic
  1](../epics/epic-1-expand-toolchain-components/EPIC_1.md)
  ([issue #18](https://github.com/julienlegoux/vps-boot/issues/18), milestone 1).
* **Confirmed**: `tmux` is fully gone from the working tree — only git history
  and this bundle's log still mention it.
* **Audit findings** that shaped the change, none of them visible from the
  planning docs alone:
  * `bl_update` installs no compiler. `build-essential` reaches most boxes only
    as a side effect of Hermes' installer, so unticking Hermes silently removes
    `gcc`. Moved into the baseline.
  * `prompt_multiselect` redraws with a blind `printf '\033[%dA' "$n"`, which
    corrupts the display once the block scrolls past the terminal fold. Latent
    at 12 components, breaking at 23.
  * The wizard's QuickStart label advertises five tools while installing twelve
    — it was never updated as components landed. Replaced with registry-computed
    counts.
  * Three upstream installers (`pi.dev`, bare `rustup`, Hermes) prompt
    interactively, which hangs `step_run` silently.
* **Version audit** of all twelve existing components: nothing stale. The
  distro-default trap that nearly shipped a Java 21 is unique to Java; every
  other component resolves newest-at-install-time. One gap found —
  `check_claude` reports no version. Recorded on
  [decision 20](/changes/change-1-expand-toolchain-components/20-version-audit.md).
* **`docs/epics/` established** by this run, per the bundle rules.

## 2026-08-16

* **Update**: refreshed the map from `50c133b` to `2e2cb76` (develop). Four
  substantive commits since the creation sweep; `vps-boot.sh` grew 1501 → 1539
  lines. Re-swept only the areas the diff touched.
* **Components**: `tmux` replaced by `herdr` (`505512a`), `pnpm` and `opencode`
  added (`2e2cb76`) — the registry is now twelve components, and four of them
  install through `npm -g` behind `node`. [SPECS.md](/SPECS.md) *Architecture* and
  *Interfaces & integrations* updated.
* **`apt` migration complete**: `ba7a29b` converted the last ten `apt-get` call
  sites and the `.claude/CLAUDE.md` worked example.
  [Issue #16](https://github.com/julienlegoux/vps-boot/issues/16) verified and
  closed; [CONVENTIONS.md](/CONVENTIONS.md) no longer describes the rule as having
  legacy exceptions. Follow-through recorded on
  [decision 02](/mapping/02-apt-vs-apt-get.md).
* **Ledger**: [decision 01](/mapping/01-docs-directory-is-gitignored.md) reopened
  and re-decided — `docs/` is no longer ignored. The `.gitignore` entry was removed
  (the file is now empty) and this bundle is tracked, committed and pushed from now
  on. The original verdict is kept as history in the decision doc.
* **Corrections**: every `vps-boot.sh` line reference past `:546` was re-anchored to
  the new file; the creation sweep's "33 test cases" was wrong — there are 32
  registered `run_test` lines, and `tests/test_vps_boot.sh` is unchanged.

## 2026-08-07

* **Creation**: mapped `vps-boot` at `50c133b` — swept `vps-boot.sh` (1501 lines),
  `tests/test_vps_boot.sh` (33 cases), `README.md`, `AGENTS.md`,
  `.claude/CLAUDE.md`, and git history; wrote [SPECS.md](/SPECS.md) and
  [CONVENTIONS.md](/CONVENTIONS.md).
* **Ledger**: three ambiguities raised and decided by discussion —
  [docs/ stays gitignored](/mapping/01-docs-directory-is-gitignored.md) (bundle is
  local-only), [`apt` everywhere](/mapping/02-apt-vs-apt-get.md) (replacement of
  the ten remaining `apt-get` sites tracked as
  [issue #16](https://github.com/julienlegoux/vps-boot/issues/16)), and
  [`AGENTS.md` deleted](/mapping/03-agents-md-vs-claude-md.md) in favour of
  `.claude/CLAUDE.md`.
* **Repo changes**: `AGENTS.md` removed; `.claude/CLAUDE.md` gained the
  `Optional user creation` convention it lacked and lost the stale `NVM_VERSION`
  file-map entry.
