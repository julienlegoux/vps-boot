---
type: Decision
title: "Install modes and component rendering"
description: "Rename QuickStart to Full install, and render 23 components without overflowing the terminal."
tags: [decision, change]
timestamp: 2026-08-16T09:05:00Z
phase: change
decision: 14
slug: quickstart-scope
status: decided
verdict: "A + C - Full install / Custom with a and n hotkeys; grouped multi-column grid"
decided_via: triage
depends_on: [defaults-and-run-order, additional-agent-clis]
change: 1
change_slug: expand-toolchain-components
---

# Question

Two linked questions the user raised at triage:

1. **Naming.** QuickStart keeps installing everything — but "QuickStart" does
   not say that. Rename it **Full install**.
2. **Rendering.** At 23 components a flat list is unusable in a terminal. It
   needs to be visual.

The second is not a preference. Reading the UI code, the current rendering has
**three defects that only appear at scale**, and 23 components crosses every
threshold:

- **`prompt_multiselect` breaks on a short terminal.** It prints `n` lines, then
  redraws on every keypress with `printf '\033[%dA' "$n"` — a blind cursor-up of
  exactly `n` rows. That assumes all `n` lines are still on screen. With 23
  components plus the label and hint line, the block is 25 rows; on a standard
  80×24 terminal it has already scrolled, the cursor-up lands in the wrong
  place, and the redraw corrupts the display. Today, at 12 components, it fits.
- **The collapse summary is one unbounded line.** After confirming, the selected
  names are joined with ` · ` into a single string and piped through `sed` to
  prefix the rail. Twenty-three names is roughly 250 characters: it wraps, and
  the wrapped remainder has no rail prefix, so the left border breaks.
- **The Confirm screen has the same bug** (`vps-boot.sh:1240-1246`): the same
  ` · `-joined string passed to one `body` call.

Plus the standing finding: **the mode label already lies.** It reads
`"QuickStart|Docker · gh · Node LTS · Bun · Claude Code (defaults)"`
(`vps-boot.sh:1204`) — five tools, twelve installed. Any hardcoded enumeration
rots the same way, so whatever replaces it must be computed from the registry.

Component count after this change: **23**.

# Options

**Naming**

- **A. `Full install` / `Custom`**, plus `a` (all) and `n` (none) hotkeys in the
  multi-select. Two modes; "baseline only" is Custom + `n`, two keystrokes.
- **B. `Full install` / `Secure only` / `Custom`** — a third mode for
  baseline-only. More explicit, one more radio line.

**Rendering**

- **C. Grouped multi-column grid.** Components carry a group; the multi-select
  lays them out as a grid with the group name in a left gutter. 23 components
  become ~13 rows. Needs a new `COMPONENT_GROUP` registry field and 2-D
  (←/→ as well as ↑/↓) navigation.
- **D. Scrolling viewport.** Keep one-per-line and 1-D navigation, render only a
  window of ~12 rows with `↑ 4 more` / `↓ 7 more` markers. Fixes the terminal-
  height bug with much less code; still scrolls past 23 items to find one.
- **E. Grouped single column with headers.** Most readable per item, worst
  vertically — 23 rows plus 6 headers is 29, further past the fold than today.

# Recommendation

**A + C.**

On naming: `Full install` says what it does, and the `a`/`n` hotkeys make a
third mode unnecessary — unticking 23 boxes by hand was the only real argument
for one. Keep the labels computed:

```
◇  Install mode
│
│  ● Full install   everything — 23 tools
│                   core 4 · languages 5 · packaging 3 · agents 6 · cloud 3 · infra 2
│  ○ Custom         pick what you need
```

The counts come from the registry, so this label cannot go stale the way the
current one did.

On rendering, the grid earns its cost — it is also the only option that fixes
the terminal-height bug *and* makes 23 items scannable:

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

Sixteen rows including the header — fits an 80×24 terminal with room, uses the
existing glyph vocabulary (`◉`/`◌`, the `│` rail, orange title, dim hints), and
groups the list into chunks small enough to scan. Column width 21, three
columns: `3 + 10 + 3×21 = 76`, inside 80. The script already calls `tput`, so
narrow terminals drop to two columns or one.

Then the summary lines, which are the same fix applied twice — never join an
unbounded list into one line. Full selection collapses to counts; a partial
selection lists the **skipped** items instead when they are fewer, which is
almost always the shorter and more informative half:

```
│  install   all 23  ·  core 4 · languages 5 · packaging 3 · agents 6 · cloud 3 · infra 2
│  install   20 of 23  ·  skipped: Hermes · Caddy · Rust
```

**Proposed groups** (23 components):

| Group | Components |
|---|---|
| `core` (4) | `sudo_nopasswd`, `tools`, `docker`, `gh` |
| `languages` (5) | `node`, `python`, `go`, `java`, `rust` |
| `packaging` (3) | `bun`, `pnpm`, `uv` |
| `agents` (6) | `claude`, `opencode`, `codex`, `gemini`, `pi`, `hermes` |
| `cloud` (3) | `vercel`, `hostinger`, `neon` |
| `infra` (2) | `caddy`, `herdr` |

**This reopens part of [01-approach](01-approach.md).** `COMPONENT_GROUP` is a
new registry field and the grid is a real rewrite of `prompt_multiselect`, so
"extend only, don't touch the registry mechanism" no longer holds in full. That
is the honest cost of this option — see the refresh note on that doc. **D** is
the fallback that keeps 01 intact: it fixes the correctness bug and none of the
scannability.

# Verdict

**A + C.** Accepted at triage.

**Naming**: `Full install` / `Custom`, two modes. `a` (all) and `n` (none)
hotkeys in the picker make a third "Secure only" mode unnecessary — baseline
only is Custom + `n`. Mode labels carry counts computed from the registry, never
a hardcoded enumeration.

**Rendering**: grouped multi-column grid, six groups (`core` 4, `languages` 5,
`packaging` 3, `agents` 6, `cloud` 3, `infra` 2), three columns of width 21,
degrading to fewer columns on narrow terminals via `tput`. This fixes the
terminal-height corruption as well as the scannability problem.

**Summaries**: never join an unbounded list into one line. Full selection →
group counts; partial selection → list the *skipped* items when they are the
shorter half. Applies to both the picker's collapse and the Confirm screen.

Accepted cost: `COMPONENT_GROUP` is a new registry field and
`prompt_multiselect` is substantially rewritten, which narrows
[01](01-approach.md)'s "extend only" to the dependency question. Option D
(scrolling viewport) was the fallback that would have preserved it; not taken.
