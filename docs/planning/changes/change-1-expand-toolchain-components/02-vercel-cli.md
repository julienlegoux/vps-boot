---
type: Decision
title: "Vercel CLI"
description: "How does the Vercel CLI get installed, and does it get a sign-in hint?"
tags: [decision, change]
timestamp: 2026-08-16T09:05:00Z
phase: change
decision: 02
slug: vercel-cli
status: decided
verdict: "A - npm install -g vercel, sign-in hint: vercel login"
decided_via: triage
depends_on: [approach]
change: 1
change_slug: expand-toolchain-components
---

# Question

Requested explicitly. The Vercel CLI ships as the `vercel` npm package; the
documented install is `npm i -g vercel`. That is byte-for-byte the pattern
`install_bun`, `install_pnpm`, `install_claude` and `install_opencode` already
use (`vps-boot.sh:533-597`), so the install body is one line and the ordering
constraint is the existing "after `node`" one.

Authentication uses `vercel login`, as documented in the
[Vercel CLI reference](https://vercel.com/docs/cli/login).
The previously specified `--no-browser` flag was incorrect and was removed
on 2026-09-05 following the user's correction.

`register`'s optional 8th argument is a sign-in hint printed in the `do_check`
footer; `gh`, `claude`, `opencode` and `hermes` all set one.

# Options

- **A. `npm install -g vercel`, sign-in hint `vercel login`** —
  matches the existing npm components and the documented login command.
- **B. Same install, hint mentions `VERCEL_TOKEN`** — correct for CI, but this
  box is an interactive dev environment, and an env var is not something a
  footer hint can set for the operator.
- **C. Install through `bun`/`pnpm` instead of `npm`** — no benefit; `npm` is
  the established convention here.

# Recommendation

**A.** One-line installer, `check_vercel` following the `check_pnpm` shape
(`command -v vercel` then `vercel --version`), registered `system` scope after
`node`. The sign-in hint is simply `vercel login`.

# Verdict

**A.** Accepted at triage.

`npm install -g vercel`, `system` scope, registered in the `cloud` group with
`hostinger` and `neon`. `check_vercel` on `vercel --version`. Sign-in hint names
`vercel login`.
