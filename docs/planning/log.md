# Log

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
