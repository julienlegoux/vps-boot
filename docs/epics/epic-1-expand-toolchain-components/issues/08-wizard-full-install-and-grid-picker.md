---
type: Issue
title: "Rework the wizard: Full install mode and grouped grid picker"
description: "Rename QuickStart to Full install with registry-computed labels, rewrite prompt_multiselect as a grouped multi-column grid with a/n hotkeys, and stop both summary surfaces joining unbounded lists into one line."
tags: [epic-1]
timestamp: 2026-08-16T11:30:00Z
epic: 1
issue: 08
slug: wizard-full-install-and-grid-picker
size: M
status: open
gh_issue: 26
depends_on: [1]
resource: https://github.com/julienlegoux/vps-boot/issues/26
---

# Rework the wizard: Full install mode and grouped grid picker

## Summary

The picker does not survive twenty-three components, and this is a correctness
fix before it is a readability one. `prompt_multiselect` redraws on every keypress
with a blind `printf '\033[%dA' "$n"` (`vps-boot.sh:333`) — a cursor-up of exactly
`n` rows, which assumes all `n` lines are still on screen. At 23 components plus
the label and hint line the block is 25 rows; on a standard 80×24 terminal it has
already scrolled, the cursor-up lands in the wrong place, and the redraw corrupts
the display. At today's twelve it fits, which is why the bug is invisible now.

Two more defects appear at the same scale: the picker's collapse summary
(`:340-359`) and the Confirm screen (`:1240-1246`) both join every selected name
into one ` · `-separated string. Twenty-three names is roughly 250 characters —
it wraps, and the wrapped remainder carries no rail prefix, so the left border
breaks.

And the mode label already lies: it reads `Docker · gh · Node LTS · Bun · Claude
Code (defaults)` (`vps-boot.sh:1204`) — five tools named, twelve installed. Any
hardcoded enumeration rots the same way, so the replacement is computed from the
registry.

## Scope

**Mode rename and computed labels** (`vps-boot.sh:1201-1225`).

- `QuickStart` becomes `Full install`. Two modes, not three: `a` (all) and `n`
  (none) hotkeys in the picker make a separate "baseline only" mode unnecessary —
  baseline only is Custom + `n`, two keystrokes.
- Both mode labels are **computed from the registry**, never enumerated. Target
  rendering:

  ```
  ◇  Install mode
  │
  │  ● Full install   everything — 23 tools
  │                   core 4 · languages 5 · packaging 3 · agents 6 · cloud 3 · infra 2
  │  ○ Custom         pick what you need
  ```

  The counts must respect `component_is_applicable` (`vps-boot.sh:1111-1114`), so
  root-only mode shows 22 with `core 3`, not 23.

**Grid picker** — rewrite `prompt_multiselect` (`vps-boot.sh:289-378`) and
`_msel_print_line` (`:362-378`) as a grouped multi-column grid:

```
◇  Components                                        23 selected · 0 skipped
│  ↑↓←→ move · space toggle · a all · n none · enter confirm
│
│  core      ◉ Passwordless sudo  ◉ CLI essentials     ◉ Docker + Compose
│            ◉ GitHub CLI
│  languages ◉ Node LTS           ◉ Python + pip       ◉ Go
│            ◉ Java 25            ◉ Rust
│  packaging ◉ Bun                ◉ pnpm               ◉ uv
│  agents    ◉ Claude Code        ◉ opencode           ◉ Codex CLI
│            ◉ Gemini CLI         ◉ pi                 ◉ Hermes
│  cloud     ◉ Vercel CLI         ◉ Hostinger CLI      ◉ Neon CLI
│  infra     ◉ Caddy              ◉ herdr
```

- Group name in a left gutter; three columns of width 21 — `3 + 10 + 3×21 = 76`,
  inside 80. Degrade to two columns or one on narrow terminals via `tput cols`,
  which the script already calls.
- 2-D navigation: `←`/`→` as well as `↑`/`↓` (keep the existing `j`/`k`
  aliases), plus `a` (select all) and `n` (select none).
- The redraw must not assume the block is on screen. Whatever the mechanism —
  recomputing the row count from the rendered grid, or a bounded viewport — the
  fix is that the cursor-up count matches what was actually printed.
- Keep the existing glyph vocabulary and colors: `◉`/`◌`, the `│` rail, orange
  title, dim hints, cyan cursor. Keep the calling contract intact —
  `prompt_multiselect` writes to `PROMPT_MSEL_RESULT`, and every read stays
  `< /dev/tty`.
- The option string gains the group. It is currently
  `"key|name|desc|default"` (`vps-boot.sh:1214`); extend it rather than
  introducing a second channel.

**Bounded summaries** — the same fix applied twice; never join an unbounded list
into one line:

```
│  install   all 23  ·  core 4 · languages 5 · packaging 3 · agents 6 · cloud 3 · infra 2
│  install   20 of 23  ·  skipped: Hermes · Caddy · Rust
```

- A full selection collapses to group counts. A partial selection lists the
  **skipped** items when they are the shorter half, which is almost always the
  more informative one.
- Apply to both the picker's collapse (`vps-boot.sh:340-359`) and the Confirm
  screen (`:1237-1247`).

**Test and doc updates the rename forces** — these are not optional cleanup, the
suite fails without them:

- `tests/test_vps_boot.sh:148`, `:230`, `:255` — three `prompt_radio` stubs
  return `value=QuickStart` for the `"Install mode"` case.
- `tests/test_vps_boot.sh:610` — `test_readme_documents_new_defaults` greps the
  README for `QuickStart.*Passwordless sudo.*only when.*create a user`.
- `tests/test_vps_boot.sh:635` — the `run_test` label
  `"root QuickStart cmd_install flow filters user-only work"`.
- `README.md:54` — the QuickStart sentence the assertion above matches, plus any
  other README mention of the mode name.
- `docs/planning/SPECS.md` — the Interactive TTY section under Interfaces.

## Out of scope

- **Further wizard UI work** beyond the picker and the two summary surfaces —
  the user/port/confirm prompts stay as they are.
- A prompt offering to open 80/443 for Caddy. Noted as worth revisiting in issue
  07; not built here.
- The scrolling-viewport alternative (option D) as a *substitute* for the grid.
  It was the fallback and was not taken. It may still be the mechanism *inside*
  the grid if that is how the redraw bug gets fixed.
- Changing which components exist or their defaults. All 23 stay default-on.

## Acceptance criteria / Definition of done

- [ ] `bash tests/test_vps_boot.sh` passes with **no case renamed away** — the
      three stubs, the README assertion and the label above are updated to the new
      mode name, and the count stays at 33 (32 + issue 01's invariant).
- [ ] `grep -rn QuickStart vps-boot.sh tests/ README.md docs/` returns nothing.
- [ ] `bash -n vps-boot.sh` is clean.
- [ ] The mode label is computed: `grep -n 'Install mode' -A 4 vps-boot.sh` shows
      no hardcoded tool names, and the count shown in root-only mode differs from
      created-user mode by exactly one (`sudo_nopasswd`).
- [ ] On an **80×24** terminal with 23 components registered, driven by hand:
      the picker renders inside the border with no wrapping and no corruption
      after navigating to the last row and back; `a` ticks all 23 and `n` unticks
      all 23, with the header count updating.
- [ ] On the same terminal, the collapse summary and the Confirm screen both
      render on one rail-prefixed line each for a full selection, and the Confirm
      screen shows `skipped: …` for a partial selection with three items
      unticked.
- [ ] Narrow-terminal degradation is exercised: resize to 60 columns and confirm
      the grid drops to fewer columns rather than wrapping.
- [ ] Selecting nothing still reaches the "baseline only" Confirm line
      (`vps-boot.sh:1237-1239`) and the install runs.
- [ ] `README.md` and `docs/planning/SPECS.md` updated in the same commit.

## Relevant files / areas

- `vps-boot.sh:289-378` — `prompt_multiselect` and `_msel_print_line`; `:333` is
  the blind cursor-up, `:340-359` the collapse summary.
- `vps-boot.sh:1201-1225` — the install-mode radio and the selection loop.
- `vps-boot.sh:1237-1247` — the Confirm screen's `install` line.
- `vps-boot.sh:1111-1114` — `component_is_applicable`, which the counts must
  respect.
- `vps-boot.sh:208-287` — `prompt_radio`, for the collapse idiom and the
  established rendering vocabulary.
- `tests/test_vps_boot.sh:144-263` — the install-flow fixtures and their
  `prompt_radio` / `prompt_multiselect` stubs.
- `tests/test_vps_boot.sh:606-626`, `:635` — the README assertion and the test
  label.
- `README.md:54`, `docs/planning/SPECS.md` (Interfaces → Interactive TTY).
- `docs/planning/changes/change-1-expand-toolchain-components/14-quickstart-scope.md`
  — the full rationale and both target renderings.

## Dependencies

- **Blocked by**: issue 01 (`COMPONENT_GROUP` is what the grid lays out by).
- **Blocks**: nothing, but note it renders whatever the registry holds at merge
  time. Verifying the 80×24 criterion at the real 23 components requires issues
  03–07 merged; if this lands first, re-verify during issue 09 rather than
  claiming it at 12 components.

## PR size note

Target ~500 changed lines; if this grows past ~1000, split it before opening the
PR. Expect ~250, and this is the one issue in the epic with real design content
rather than repeated blocks. If it does overrun, the natural cut is the grid
rewrite in one PR and the two summary surfaces plus the mode rename in another.
