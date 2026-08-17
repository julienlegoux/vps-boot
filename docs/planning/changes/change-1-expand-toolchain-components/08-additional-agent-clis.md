---
type: Decision
title: "Additional agent CLIs"
description: "Do Codex CLI and Gemini CLI join claude, opencode, hermes and pi?"
tags: [decision, change]
timestamp: 2026-08-16T08:12:00Z
phase: change
decision: 08
slug: additional-agent-clis
status: decided
verdict: "A — add both Codex CLI and Gemini CLI"
decided_via: triage
depends_on: [pi-coding-agent]
change: 1
change_slug: expand-toolchain-components
---

# Question

Part of "what else is missing". `SPECS.md` describes the box's primary use case
as autonomous AI environments, and the registry already carries three agents
(`claude`, `opencode`, `hermes`), with `pi` proposed as a fourth
([04](04-pi-coding-agent.md)). The two obvious absentees are the other
first-party terminal agents:

| Tool | Package | Binary | Notes |
|---|---|---|---|
| Codex CLI | `@openai/codex` `0.147.0` | `codex` | Rust binary shipped via per-platform optional deps (linux x64/arm64 covered); `engines.node >= 16` |
| Gemini CLI | `@google/gemini-cli` `0.55.1` | `gemini` | `engines.node >= 20` |

Both are one-line `npm -g` installs behind `node`, identical in shape to the
four npm components already registered. Both authenticate interactively on first
run (OAuth against a provider account) or via an API-key environment variable —
same footer-hint treatment as `claude` and `opencode`.

The cost is not install complexity, it is registry weight: with `pi`, five
agents default to on, and QuickStart installs everything. That is roughly two
minutes of extra install time and five agents an operator may only want one of.

# Options

- **A. Add both** — the box can host whichever agent the operator's subscription
  covers, decided at use time rather than provision time.
- **B. Add Codex only** — the most-used of the two.
- **C. Add neither** — four agents is already more than anyone runs at once.
- **D. Add both but register them default-off** — they appear in the Custom
  multi-select, QuickStart skips them. Note this breaks the registry's current
  invariant that every component defaults to `1`; see
  [10-defaults-and-run-order](10-defaults-and-run-order.md).

# Recommendation

**A.** They cost one line each and the marginal install time is small next to
`docker` and the deadsnakes Python build. The value of this script is that a
fresh VPS is usable immediately without remembering what it lacks; an agent CLI
that is missing costs more attention later than it saves now. Keeping every
component default-on also preserves the "QuickStart = everything" property that
makes the wizard's first prompt meaningful.

If the registry does start to feel bloated, the right fix is grouping in the
multi-select UI, not dropping tools — and that is a separate change.

# Verdict

**A — add both.** Accepted at triage.

`codex` (`npm i -g @openai/codex`) and `gemini` (`npm i -g @google/gemini-cli`)
join `claude`, `opencode`, `hermes` and `pi` in the registry, both `system`
scope, both registered after `node`, both with a sign-in hint in the `do_check`
footer.

Note the option-D concern about registry weight is no longer hypothetical:
[14-quickstart-scope](14-quickstart-scope.md) was opened after this verdict to
decide what QuickStart installs, precisely because six agents default-on is too
much for one mode. That decision, not this one, is where the default-on question
now lives.
