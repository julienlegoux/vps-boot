---
type: Decision
title: "Neon CLI"
description: "Add neonctl, the Neon Postgres CLI."
tags: [decision, change]
timestamp: 2026-08-16T09:05:00Z
phase: change
decision: 17
slug: neon-cli
status: decided
verdict: "A - npm install -g neonctl"
decided_via: triage
depends_on: [approach]
change: 1
change_slug: expand-toolchain-components
---

# Question

Pulled back in from [09-considered-and-excluded](09-considered-and-excluded.md)
at the user's request.

Facts: package `neonctl`, version `3.2.2`, `engines.node >= 20.19.0` — satisfied
by the NodeSource LTS the `node` component installs. It declares **two** binary
names, `neon` and `neonctl`, both pointing at `bin/cli.js`.

That second name is worth a beat. `neon` is a short, generic command; nothing
else in this registry claims it today, but the collision surface is real. The
check function should probe `neonctl` — the unambiguous name — rather than
`neon`.

Auth is `neonctl auth`, an OAuth browser flow, with `NEON_API_KEY` as the
headless alternative. Same footer-hint treatment as `vercel` and `hostinger`.

Install is `npm install -g neonctl`, identical in shape to the eight other npm
components.

# Options

- **A. `npm install -g neonctl`**, `system` scope, after `node`, check on
  `neonctl --version`, sign-in hint naming `NEON_API_KEY` for the headless case.
- **B. Skip** — the user's earlier exclusion reasoning, that one CLI per SaaS is
  a pattern worth deciding deliberately rather than accreting.

# Recommendation

**A**, now that the user has decided. The "one CLI per SaaS" concern from the
exclusion list is answered rather than ignored: Vercel, Hostinger and Neon are
this project's actual hosting, VPS and database providers, so the set is bounded
by the stack rather than open-ended. If a fourth arrives without that
justification, the pattern question comes back.

Register it in the cloud group next to `vercel` and `hostinger`, not in the
generic npm cluster — see [14](14-quickstart-scope.md) on grouping.

# Verdict

**A.** Accepted at triage.

`npm install -g neonctl`, `system` scope, `cloud` group with `vercel` and
`hostinger`. `check_neon` probes **`neonctl`**, not the package's second and
more collision-prone binary name `neon`. Sign-in hint: `neonctl auth`, with
`NEON_API_KEY` for the headless case.

The "one CLI per SaaS" concern from [09](09-considered-and-excluded.md) is
answered rather than dropped: Vercel, Hostinger and Neon are this project's
actual hosting, VPS and database providers, so the set is bounded by the stack.
A fourth without that justification reopens the question.
