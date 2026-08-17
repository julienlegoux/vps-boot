---
type: Decision
title: "Defaults and run order"
description: "Where the new components sit in the registry, and whether they all default to on."
tags: [decision, change]
timestamp: 2026-08-16T09:05:00Z
phase: change
decision: 10
slug: defaults-and-run-order
status: decided
verdict: "A (ordering half) - group by kind in registration order; defaults deferred to decision 14"
decided_via: triage
depends_on: [approach, vercel-cli, hostinger-cli, pi-coding-agent, java-jdk, shell-essentials, uv, additional-agent-clis]
change: 1
change_slug: expand-toolchain-components
---

# Question

Registration order **is** run order (`vps-boot.sh:396-407`), and it is the only
mechanism enforcing that npm-based components run after `node`. All twelve
current components register with `COMPONENT_DEFAULT` = `1`, so QuickStart
installs everything and Custom mode starts with every box ticked.

The additions and their constraints:

| Component | Constraint | Proposed position |
|---|---|---|
| `tools` | none (apt) | early — right after `sudo_nopasswd`, before anything that might want a compiler |
| `vercel` | after `node` | with the npm cluster |
| `pi` | after `node` | with the npm cluster |
| `codex` | after `node` | with the npm cluster |
| `gemini` | after `node` | with the npm cluster |
| `uv` | none | after `python`, for readability |
| `java` | none (apt) | with the language toolchains, after `go` |
| `hostinger` | none (tarball) | near `gh`, or at the end with the other non-apt installers |

Going from 12 to 19-20 components also changes what the wizard's multi-select
looks like — currently one screen of twelve rows.

# Options

- **A. All default-on, appended in the positions above** — preserves "QuickStart
  = everything"; every install gets longer for everyone.
- **B. All default-on, but appended strictly at the end of the registry** —
  smallest possible diff (no insertions between existing blocks, so existing
  line anchors in SPECS.md stay valid), at the cost of a run order that reads as
  an accretion log rather than a grouping.
- **C. Mixed defaults** — cloud CLIs and extra agents default-off. Breaks the
  current uniform invariant and means QuickStart silently gives you less than
  the tool list suggests.

> **Refreshed after [08](08-additional-agent-clis.md) was decided.** The
> defaults half of this decision has moved: the user raised QuickStart bloat at
> triage, and [14-quickstart-scope](14-quickstart-scope.md) now owns whether
> components stay uniformly default-on. **Option C below is no longer this
> doc's to reject** — read it as live in 14. What remains here is run order.

# Recommendation

**A, restricted to the ordering half.** Grouping by kind is worth the slightly
larger diff: the Components
section is read top to bottom by every future contributor, and `.claude/CLAUDE.md`
already documents "order = run order". Keeping all defaults at `1` keeps the
wizard honest — the QuickStart path is the one most installs take, and a
component that exists but is off by default is a component most operators never
discover.

Three riders. `tools` goes early precisely because `build-essential`'s split
into `bl_update` ([06](06-shell-essentials.md)) may not be accepted, and if it
lands in `tools` instead then position matters. `tools` must also precede
`hermes`, whose installer prompts to install `ripgrep` when it is missing. And
SPECS.md's line-number anchors past the insertion points must be re-anchored in
the same commit ([13](13-acceptance-criteria.md)).

On defaults, the recommendation is now simply "whatever
[14](14-quickstart-scope.md) decides" — with `codex` and `gemini`
([08](08-additional-agent-clis.md), decided) inheriting the same treatment as
the other agent CLIs rather than getting their own rule.

# Verdict

**A, ordering half only.** Accepted at triage.

Components register grouped by kind — `core`, `languages`, `packaging`,
`agents`, `cloud`, `infra` — in the order [14](14-quickstart-scope.md) lists.
`tools` early (before `hermes`); every npm-based component after `node`.

Defaults are settled by [14](14-quickstart-scope.md): all stay `1`, and Full
install means everything. SPECS.md's line anchors past the insertion points are
re-anchored in the same commit ([13](13-acceptance-criteria.md)).
