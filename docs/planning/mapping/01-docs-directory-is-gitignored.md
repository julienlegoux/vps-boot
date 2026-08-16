---
type: Decision
title: "docs/ is gitignored"
description: "The planning bundle lives under docs/, which .gitignore excludes — should docs/planning/ be tracked?"
tags: [decision, mapping]
timestamp: 2026-08-16T07:28:00Z
phase: mapping
decision: 01
slug: docs-directory-is-gitignored
status: decided
verdict: "Un-ignore docs/ entirely — the .gitignore entry is removed and the planning bundle is tracked"
decided_via: discussion
depends_on: []
---

# Question

`.gitignore` contained a single entry: `docs`. Every path under `docs/` — including
the `docs/planning/` bundle this mapping produces — was excluded from version
control. `git check-ignore -v docs/planning/SPECS.md` confirmed
`.gitignore:1:docs`.

The exclusion was deliberate, not accidental. Commit `caf24d4` is titled
`feat: add .gitignore to exclude docs directory`, and commit `f9419e8`
(`chore: remove docs/superpowers folder`) removed an agent-scratch tree that had
accumulated there. `docs/` had been treated as a scratch area for agent output,
not as a deliverable.

That conflicts with how the planning bundle is meant to work: `SPECS.md` and
`CONVENTIONS.md` are read by later sessions and by downstream skills
(`define-change`, `create-issues`, `implement-epic`), and the pipeline commits and
pushes what it writes. An untracked bundle is invisible to every collaborator and
to any fresh clone, and it disappears with the working tree.

# Options

- **Un-ignore only the planning bundle** — keep `docs` ignored, add
  `!docs/planning/` (plus the `!docs/` directory re-inclusion Git requires) so
  agent scratch stays excluded while the deliverable is tracked. Narrow, preserves
  the original intent.
- **Un-ignore `docs/` entirely** — drop the `.gitignore` entry. Simplest, but
  re-admits every future agent-scratch tree that motivated the exclusion.
- **Leave `docs/` ignored** — the bundle stays local-only. Nothing is committed;
  the map is a working aid for this machine and is lost on a fresh clone.

# Recommendation

**Un-ignore only the planning bundle.** It resolves the conflict without undoing
the reason `docs` was ignored in the first place. The evidence that scratch output
was the target is direct — the only thing ever removed from `docs/` was
`docs/superpowers`, an agent artifact tree — and `docs/planning/` is a small,
hand-reviewable set of files with a different lifecycle. The alternative that
keeps the bundle untracked defeats the purpose of producing it, since every
downstream skill assumes the bundle is present in the repo.

# Verdict

**Un-ignore `docs/` entirely.** The `.gitignore` entry is removed, leaving the file
empty, and `docs/planning/` is committed and pushed with the rest of the repo. The
planning bundle is a tracked deliverable from now on: present in a fresh clone,
visible to collaborators, and available to every downstream skill without being
regenerated first.

The trade-off is accepted knowingly: nothing mechanically keeps agent scratch out
of `docs/` any more. Keeping that tree clean is a review habit rather than a
`.gitignore` rule, and a future scratch directory should be excluded by its own
narrow entry rather than by re-ignoring `docs/` wholesale.

## History

This decision was first taken on 2026-08-07 the other way — **leave `docs/`
ignored**, bundle local-only, nothing committed — and reopened on 2026-08-16 during
the refresh at `2e2cb76`. Both the original verdict and the recommendation it
overrode (track `docs/planning/` while keeping agent scratch excluded) are superseded
by the verdict above.
