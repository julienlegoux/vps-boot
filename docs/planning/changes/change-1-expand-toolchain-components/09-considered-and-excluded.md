---
type: Decision
title: "Considered and excluded"
description: "Tools weighed for the \"what else is missing\" question and ruled out of this change."
tags: [decision, change]
timestamp: 2026-08-16T07:46:56Z
phase: change
decision: 09
slug: considered-and-excluded
status: na
verdict: null
decided_via: null
depends_on: []
change: 1
change_slug: expand-toolchain-components
---

> **Confirmed at triage, with four repêchages.** The user pulled **Rust**,
> **Neon CLI**, **Caddy** and **unattended-upgrades** back in; each now has its
> own decision doc ([16](16-rust.md), [17](17-neon-cli.md), [18](18-caddy.md),
> [19](19-unattended-upgrades.md)) and is struck from the table below. The
> remainder stay out.
>
> Note [18](18-caddy.md) inherits this doc's network-posture objection rather
> than discarding it: Caddy is in, but what it does to UFW is now an open
> decision in its own right.

# Question

"What else is missing" has a long tail. These were weighed against the box's
stated purpose and left out — each is a judgment call, not a fact, so this list
needs explicit confirmation rather than being folded into a blanket accept. Any
one of them can be pulled back in.

| Candidate | Install | Why it is out |
|---|---|---|
| **Tailscale** | official apt repo | Genuinely strong for a VPS — private mesh access without exposing a port. Out because it changes the box's *network posture*, which the baseline (`bl_ufw`, `bl_ssh_harden`, `enroll_ssh_key`) owns end to end. Bolting it on as a component leaves two access models with no single decision about which one is authoritative. Deserves its own change. |
| **Cloudflare Wrangler** | `npm -g wrangler` | Sibling to the Vercel CLI. Out because nothing in the repo or the user's stack points at Cloudflare; trivial to add later. |
| **Deno** | install.sh | `bun` already covers the alternative-runtime slot. |
| **mise / asdf** | install.sh | Polyglot version managers overlap `node`, `python`, `go`, `java` and now `rust` head-on. Adopting one is a rework of five components, not an addition. |
| **Terraform / OpenTofu, AWS CLI** | apt / installer | No signal in the repo or the user's stack. |
| **PostgreSQL / Redis natively** | apt | `docker` is registered; running datastores in containers is the established path here. |
| **Swap file** | baseline work | Still out. A real gap for a 2-core VPS that now compiles Rust as well as native npm addons — `cargo build` and `node-gyp` are exactly the workloads that OOM on a small box. This is a `bl_*` change, not a component, and it was not among the repêchages. Recorded so it is not lost. |

**Struck from this list at triage** — now decided elsewhere: Rust
([16](16-rust.md)), Neon CLI ([17](17-neon-cli.md)), Caddy ([18](18-caddy.md)),
unattended-upgrades ([19](19-unattended-upgrades.md)).

# Options

Not applicable — this document exists to make the exclusions visible.

# Recommendation

Leave the remaining seven out of change 1. Flag any that should come back in,
and it moves to its own decision doc with a real recommendation.

Of what is left, **swap** is the only entry that is a defect rather than an
absence, and Rust's arrival makes it slightly worse. It belongs in a hardening
change alongside whatever else `bl_*` grows.

# Verdict

Confirmed at triage. Four items repêchés — Rust, Neon CLI, Caddy,
unattended-upgrades — each promoted to its own decision doc. The seven
remaining candidates stay out of [change 1](index.md).
