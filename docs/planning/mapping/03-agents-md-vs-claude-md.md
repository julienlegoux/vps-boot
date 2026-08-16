---
type: Decision
title: "AGENTS.md vs .claude/CLAUDE.md"
description: "Two near-duplicate agent memory files have drifted apart — which one is canonical?"
tags: [decision, mapping]
timestamp: 2026-08-07T00:33:16Z
phase: mapping
decision: 03
slug: agents-md-vs-claude-md
status: decided
verdict: "Delete AGENTS.md; .claude/CLAUDE.md is the single canonical agent instruction file"
decided_via: discussion
depends_on: []
---

# Question

The repo carries two agent-instruction files with substantially the same content:
`AGENTS.md` at the root and `.claude/CLAUDE.md`. Both describe the same file map,
the same "adding a component" worked example, the same conventions list, and the
same visual vocabulary table. They have since drifted:

- `AGENTS.md` has a seventh convention bullet, **Optional user creation**,
  documenting root-only mode (`USERNAME=root`, `bl_user` skipped, `PermitRootLogin
  yes` during install then tightened by `enroll_ssh_key`). `.claude/CLAUDE.md`
  has no such bullet, even though that behaviour is central to the current script
  (`configure_user_mode`, `component_is_applicable`, `vps-boot.sh:1057-1076`).
- `AGENTS.md` substitutes "Codex" wherever `.claude/CLAUDE.md` says "claude" —
  including in the registry example's sign-in hint and the user-scope convention —
  so it names a component the registry does not have. The registered key is
  `claude` (`vps-boot.sh:562`).
- **Both** files list `NVM_VERSION` as a constant in the file map. It no longer
  exists: `vps-boot.sh` dropped nvm for NodeSource in commit `d8eee89`, and the
  constants block (`vps-boot.sh:16-25`) has no such entry.

Keeping two hand-maintained copies is what produced the drift, and every future
component author reads whichever one their tool loads.

# Options

- **One canonical file, the other a pointer** — pick one (content merged), reduce
  the other to a one-line "see X". Kills the drift at the source; both tools still
  find instructions at the path they look for.
- **Keep both fully populated, sync them on every change** — no tooling change,
  but this is exactly the arrangement that already drifted three ways.
- **Delete one outright** — smallest tree, but whichever agent looks for the
  deleted path gets no project instructions at all.

# Recommendation

**Make `.claude/CLAUDE.md` canonical and reduce `AGENTS.md` to a pointer**, after
merging in the `Optional user creation` bullet that only `AGENTS.md` currently has
and dropping the stale `NVM_VERSION` line from the file map. `.claude/CLAUDE.md`
is the one `README.md:105` already links to as the component contract, and it uses
the correct component name (`claude`) where `AGENTS.md` says "Codex". A pointer
file keeps `AGENTS.md` working for tools that look for it without creating a
second copy to maintain.

# Verdict

**`AGENTS.md` is deleted.** `.claude/CLAUDE.md` is the single canonical agent
instruction file; no pointer file is left behind.

Two edits were made to `.claude/CLAUDE.md` before the deletion, so that removing
`AGENTS.md` loses no information and leaves no known-false statement behind:

- The **Optional user creation** convention bullet, which existed only in
  `AGENTS.md`, was merged in. It documents root-only mode, which is central to the
  current script (`configure_user_mode`, `component_is_applicable`).
- The stale `NVM_VERSION` entry was dropped from the file map. Both files listed
  it; the constant has not existed since commit `d8eee89` replaced nvm with
  NodeSource.

This overrides the recommendation above, which favoured reducing `AGENTS.md` to a
pointer rather than deleting it.
