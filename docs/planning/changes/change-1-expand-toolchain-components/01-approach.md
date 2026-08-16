---
type: Decision
title: "Approach"
description: "Extend the component registry with new install/check/register triples, or change the registry mechanism first?"
tags: [decision, change]
timestamp: 2026-08-16T09:05:00Z
phase: change
decision: 01
slug: approach
status: decided
verdict: "A (revised) - extend the registry; no COMPONENT_REQUIRES, but accept COMPONENT_GROUP for decision 14"
decided_via: triage
depends_on: []
change: 1
change_slug: expand-toolchain-components
---

# Question

The change adds several tools to `vps-boot.sh`. The registry
(`vps-boot.sh:396-407`) already makes that a three-part, purely additive edit:
`install_<key>`, `check_<key>`, and one `register` line in the Components
section. Twelve components exist today (`sudo_nopasswd`, `docker`, `gh`, `node`,
`bun`, `pnpm`, `claude`, `opencode`, `python`, `go`, `hermes`, `herdr`), and the
wizard, QuickStart defaults, run loop and verifier all iterate the registry, so
no other plumbing changes.

Audit facts that bear on the choice:

- Each existing component block is 15-25 lines. Adding 4-7 components grows
  `vps-boot.sh` from 1539 lines to roughly 1650-1700.
- Four components (`bun`, `pnpm`, `claude`, `opencode`) are `system` scope but
  install through `npm -g`, so they carry an implicit ordering dependency on
  `node` appearing earlier in the registry. There is no declared `depends_on` in
  the registry — order is the only mechanism. Most of the tools this change adds
  are also npm-based, which deepens that implicit dependency.
- The registry has no version pinning, no per-component test hook, and no
  declared dependency field.
- `SPECS.md` records single-file distribution over `curl | bash` as the point of
  the project, and `CONVENTIONS.md` states there is no `src/` split and no plan
  to introduce one.

# Options

- **A. Extend only** — write the new triples in the Components section, change
  nothing about the registry. Smallest diff, zero risk to the existing twelve.
- **B. Extend + add a declared `COMPONENT_REQUIRES` field** — make the `node`
  dependency explicit and validated instead of positional. Cheap (one array, one
  guard) but touches `register()`, the wizard's multi-select, and the run loop.
- **C. Refactor the registry into an external manifest** — kills the single-file
  distribution property. Not viable.

> **Refreshed after the user asked for a visual component list.**
> [14](14-quickstart-scope.md) recommends a grouped grid, which needs a new
> `COMPONENT_GROUP` field and a rewrite of `prompt_multiselect`. That is a
> registry-mechanism change, so **option A below is no longer available in its
> pure form** if 14's recommendation is accepted. The revised position: extend
> only *for the dependency question* (no `COMPONENT_REQUIRES`), while accepting
> the `COMPONENT_GROUP` field that 14 requires. 14's fallback option D keeps
> this doc's option A intact.

# Recommendation

**A.** The positional dependency is a real wart, but this change makes it no
worse: every new npm-based component is appended after `node`, exactly like the
four that already work. Turning the ordering contract into a declared one is a
separate concern with its own blast radius (wizard, run loop, tests) and belongs
in its own change rather than riding along with a batch of additions. Recording
it as an out-of-scope item in [12-scope-boundary](12-scope-boundary.md) keeps it
visible.

# Verdict

**A, revised.** Accepted at triage.

Extend the registry with new `install_`/`check_`/`register` triples. No
`COMPONENT_REQUIRES`: the `node`-before-npm ordering stays positional, and
making it declarative is recorded as out of scope in
[12](12-scope-boundary.md).

The one mechanism change that *is* accepted is `COMPONENT_GROUP`, required by
[14](14-quickstart-scope.md)'s grouped picker. So "extend only" holds for the
dependency question and not for presentation — a narrower version of option A
than originally written.
