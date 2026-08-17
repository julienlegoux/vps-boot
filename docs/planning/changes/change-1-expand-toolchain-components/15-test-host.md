---
type: Decision
title: "Test host"
description: "How the real-host acceptance run gets a clean Ubuntu 24.04 box, and when it is provisioned."
tags: [decision, change]
timestamp: 2026-08-16T09:05:00Z
phase: change
decision: 15
slug: test-host
status: decided
verdict: "B - reinstall VPS2 at the start of the verification phase, twice; nothing fired now"
decided_via: triage
depends_on: [acceptance-criteria]
change: 1
change_slug: expand-toolchain-components
---

# Question

Raised by the user during triage: the acceptance criteria
([13](13-acceptance-criteria.md)) require a real Ubuntu 24.04 run, and there is
a VPS available for it — VPS2, Hostinger id `1796116`, `69.62.108.65`,
`srv1796116.hstgr.cloud`, SSH alias `VPS2`. The user proposed kicking off the OS
reinstall early so the box is ready when the test is needed.

Constraints that shape the answer:

- `vps-boot.sh` **requires a genuinely fresh host**. `SPECS.md` and
  `.claude/CLAUDE.md` both state re-running `install` on a provisioned host is
  unsupported: `bl_user` fails at `useradd`, `bl_ssh_harden` has already moved
  the port, and `enroll_ssh_key` may already have locked password auth off. A
  second test run on the same box is not a test of the same code path.
- The acceptance criteria call for **two** runs — root-only QuickStart, then a
  created-user spot check ([13](13-acceptance-criteria.md), items 2 and 3). That
  is two reinstalls, not one, and neither can reuse the other's box.
- The reinstall itself (`VPS_recreateVirtualMachineV1` via the `hostinger`
  plugin) is destructive and irreversible, and takes minutes, not hours.
- Testing SSH hardening on the box also means the *test* changes the SSH port
  and may lock down password auth — so the operator's own access to VPS2 changes
  during each run.

# Options

- **A. Reinstall immediately, now, at planning time.** The box is warm and
  waiting. Cost: it sits unused for however long the epic takes to implement,
  and it will need reinstalling again anyway before run 1, because run 1 must
  start from a genuinely untouched host.
- **B. Reinstall as the first step of the implementation's verification phase**,
  once the code is written and the local test suite is green — then again
  between run 1 and run 2.
- **C. Use a throwaway host instead** (a second provider, or a local
  multipass/VM). Keeps VPS2 out of it entirely, but adds a dependency the
  project does not have today.
- **D. Reinstall now *and* before each run** — A plus B. Costs nothing but a few
  extra minutes of provisioning and gives a warm box for any exploratory poking
  during implementation.

# Recommendation

**B**, unless the box is wanted warm for other reasons.

The reasoning is only about ordering, not about willingness: because run 1 needs
an untouched host and the two acceptance runs need one reinstall each, a
reinstall performed today is superseded by the one performed before run 1. It
buys a warm box during implementation, which the implementation does not need —
the code is written and unit-tested locally, and the local harness never touches
a host.

**D** is the right answer if the intent is to have VPS2 available for manual
exploration while the epic is being built — the extra reinstall costs minutes.

Whichever is chosen, the epic should record: two reinstalls minimum, and each
`install` run ends with the operator's SSH access on a new port with password
auth potentially disabled — so the port and the enrollment choice for each run
belong in the test notes before the run, not after.

**Nothing has been fired.** VPS recreation is destructive and irreversible, and
per the standing rule it needs an explicit go-ahead naming the moment, not a
verdict on this doc alone.

# Verdict

**B.** Accepted at triage.

VPS2 is reinstalled at the **start of the verification phase**, not now — a
reinstall done at planning time would be superseded by the one run 1 requires
anyway. Two reinstalls minimum: one before the root-only Full install run, one
before the created-user spot check.

Each run's SSH port and enrollment choice go in the test notes **before** the
run, since `install` moves the port and may disable password auth, changing the
operator's own access to the box.

**Nothing has been fired.** Recreation still needs an explicit go-ahead naming
the moment; this verdict decides *when*, not *that it may proceed unattended*.
