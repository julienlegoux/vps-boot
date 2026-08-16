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
verdict: "A - npm install -g vercel, sign-in hint "vercel login --no-browser""
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

The open part is authentication. `vercel login` opens a browser, which a
headless VPS does not have. Two documented headless paths exist:
`vercel login --no-browser`, which prints a URL to paste elsewhere, and the
`VERCEL_TOKEN` environment variable, which the CLI picks up automatically.

`register`'s optional 8th argument is a sign-in hint printed in the `do_check`
footer; `gh`, `claude`, `opencode` and `hermes` all set one.

# Options

- **A. `npm install -g vercel`, sign-in hint `vercel login --no-browser`** —
  matches the four existing npm components and points at the path that actually
  works without a browser.
- **B. Same install, hint mentions `VERCEL_TOKEN`** — correct for CI, but this
  box is an interactive dev environment, and an env var is not something a
  footer hint can set for the operator.
- **C. Install through `bun`/`pnpm` instead of `npm`** — no benefit; `npm` is
  the established convention here.

# Recommendation

**A.** One-line installer, `check_vercel` following the `check_pnpm` shape
(`command -v vercel` then `vercel --version`), registered `system` scope after
`node`. The sign-in hint names `--no-browser` explicitly because the bare
`vercel login` hangs on a headless host — that is exactly the kind of
non-obvious operational detail the footer exists for. Mention `VERCEL_TOKEN` in
the same hint line as the non-interactive alternative if it fits the width.

# Verdict

**A.** Accepted at triage.

`npm install -g vercel`, `system` scope, registered in the `cloud` group with
`hostinger` and `neon`. `check_vercel` on `vercel --version`. Sign-in hint names
`vercel login --no-browser` — the bare `vercel login` hangs on a headless host —
with `VERCEL_TOKEN` as the non-interactive alternative.
