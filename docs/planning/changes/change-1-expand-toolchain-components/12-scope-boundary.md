---
type: Decision
title: "Scope boundary"
description: "Adjacent problems the audit surfaced that this change deliberately does not fix."
tags: [decision, change]
timestamp: 2026-08-16T09:05:00Z
phase: change
decision: 12
slug: scope-boundary
status: decided
verdict: "A - all seven adjacent concerns stay out; declared dependencies and CI raised as follow-up issues"
decided_via: triage
depends_on: [approach]
change: 1
change_slug: expand-toolchain-components
---

# Question

The audit surfaced several real problems next to the code this change touches.
Naming them as OUT is what keeps a batch of component additions from becoming an
open-ended refactor.

Candidates for exclusion:

1. **Declared component dependencies.** The `node`-before-npm-components
   ordering is positional and unvalidated ([01](01-approach.md)). This change
   adds four more components that rely on it.
2. **Re-run idempotency.** `.claude/CLAUDE.md` and `SPECS.md` both state
   re-running `install` on a provisioned host is unsupported (`bl_user` fails at
   `useradd`). Anyone adding components to an existing box today has no path
   other than running the individual `install_*` by hand.
3. **Version pinning / release process.** No component pins a version; there are
   no git tags and no changelog. `hostinger` resolving "latest" over the GitHub
   API extends that pattern.
4. **The `install_hermes` hardcoded sudoers path** (`vps-boot.sh:687`, `:690`),
   recorded in `CONVENTIONS.md` as the one deviation from the `VPS_BOOT_*`
   override rule.
5. **CI.** There is no `.github/`; nothing runs the test suite. This change adds
   a test ([11](11-verification.md)) that nothing will run automatically.
6. **Multi-select UI grouping.** Nineteen flat rows in one wizard screen.
7. **Token/credential provisioning.** Three of the new tools (`vercel`,
   `hostinger`, and the agent CLIs) need credentials. The script could prompt
   for and write them.

# Options

- **A. All seven OUT** — this change is additive only.
- **B. Pull in (1) and (5)** — declared dependencies plus a CI workflow, because
  both get riskier as the registry grows.
- **C. Pull in (7)** — credential prompts, since a box with CLIs and no tokens
  is half-provisioned.

# Recommendation

**A.** Every one of these is a legitimate piece of work and none of them is
*this* piece of work. (7) in particular should stay out on its own merits, not
just for scope: writing API tokens to disk during a provisioning run — a
Hostinger token that can rebuild a VPS, in particular — is a security decision
that deserves its own change, not a wizard prompt bolted onto a batch of
installs. The existing sign-in-hint footer is the right amount of help.

(1) and (5) are the two most likely to be regretted; both should be raised as
follow-up issues rather than silently dropped.

# Verdict

**A.** Accepted at triage. All seven stay out:

1. Declared component dependencies (`COMPONENT_REQUIRES`) — **follow-up issue**
2. Re-run idempotency on a provisioned host
3. Version pinning and a release process — see [20](20-version-audit.md), which
   confirms nothing is pinned today and that this is deliberate
4. `install_hermes`' hardcoded sudoers path
5. CI — **follow-up issue**
6. Multi-select UI grouping — *partially overtaken*: [14](14-quickstart-scope.md)
   adds grouping to the picker, so what remains out is only further UI work
7. Token/credential provisioning — out on the merits, not just scope: writing a
   Hostinger token that can rebuild a VPS to disk during provisioning is a
   security decision needing its own change

One addition since this doc was written: **swap** ([09](09-considered-and-excluded.md))
is also out, and Rust's arrival makes it marginally more pressing.
