---
type: Decision
title: "Verification"
description: "What gets tested, given the harness cannot exercise network installers."
tags: [decision, change]
timestamp: 2026-08-16T09:05:00Z
phase: change
decision: 11
slug: verification
status: decided
verdict: "A + D - registry-invariant test, plus a real-host run as the acceptance gate"
decided_via: triage
depends_on: [approach]
change: 1
change_slug: expand-toolchain-components
---

# Question

`tests/test_vps_boot.sh` has 32 cases and, per `SPECS.md`, deliberately does not
cover "the network-dependent `install_*` bodies" or "anything requiring a real
Ubuntu host". So none of the new installers can be unit-tested as such, and
`test_readme_documents_new_defaults` (`tests/test_vps_boot.sh:606`) asserts only
SSH/user-mode wording — it does not check the toolchain table, so adding rows
breaks nothing.

What *is* testable without a host is the registry contract itself.
`CONVENTIONS.md` states the triple `install_x` / `check_x` / `register x` "must
agree — that triple is the contract", and nothing enforces it: a typo in a
`register` line produces a component whose install silently resolves to a
non-existent function name, and the failure surfaces only on a real VPS run.
Going from 12 to ~19 components makes that a live risk rather than a theoretical
one.

# Options

- **A. One registry-invariant test** — iterate `COMPONENTS`, assert for each key
  that `COMPONENT_INSTALL`/`COMPONENT_CHECK` are non-empty and that both name
  functions that are actually declared (`declare -F`), and that
  `COMPONENT_SCOPE` is `system` or `user`. ~15 lines, catches every typo in the
  class, protects all 19 components and every future one.
- **B. A. plus a `--dry-run` mode** for install bodies. Much larger; would need
  every installer restructured around a guard.
- **C. No new tests** — consistent with the existing "installers are untested"
  stance, and rely on a real VPS run.
- **D. Real-host verification only** — provision a throwaway VPS, run
  `install`, then `check`.

# Recommendation

**A**, plus **D** as the acceptance gate. The invariant test is cheap, matches
the harness's existing style (return codes, no assertion helpers, registered
with a `run_test` line), and closes the one failure mode this change actually
introduces. It is not a substitute for running the thing: the only proof that
`hostinger`'s tarball extracts, that `pi` starts, and that `JAVA_HOME` resolves
is a real Ubuntu 24.04 host, which is what `do_check` exists for.

Explicitly not proposed: mocking `curl`/`npm`/`apt` to unit-test installer
bodies. That tests the mock.

# Verdict

**A + D.** Accepted at triage.

Add one registry-invariant test to `tests/test_vps_boot.sh`: iterate
`COMPONENTS`, assert each key's `COMPONENT_INSTALL`/`COMPONENT_CHECK` name
functions that `declare -F` finds, that `COMPONENT_SCOPE` is `system` or `user`,
and — new, from [14](14-quickstart-scope.md) — that `COMPONENT_GROUP` is one of
the six known groups. Registered with a `run_test` line like every other case.

Real-host verification is the acceptance gate, not a substitute for it; see
[13](13-acceptance-criteria.md) and [15](15-test-host.md). Not doing: mocking
`curl`/`npm`/`apt` to unit-test installer bodies.
