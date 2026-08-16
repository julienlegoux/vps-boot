---
type: Decision
title: "Acceptance criteria"
description: "What \"done\" observably means for this change."
tags: [decision, change]
timestamp: 2026-08-16T09:05:00Z
phase: change
decision: 13
slug: acceptance-criteria
status: decided
verdict: "A - full checklist, with the created-user run reduced to a spot check"
decided_via: triage
depends_on: [defaults-and-run-order, verification]
change: 1
change_slug: expand-toolchain-components
---

# Question

The repo has no CI, so "done" is a checklist someone runs, not a green tick. The
audit identified four surfaces that go stale together whenever a component is
added, and history shows they are maintained in the same commit
(`CONVENTIONS.md`: "Keep it in sync in the same commit as the code it
describes").

The four surfaces:

- `README.md` — the *Toolchain — toggleable in Custom mode* table
  (`README.md:39-52`), one row per component.
- `docs/planning/SPECS.md` — *Architecture* names the count and lists every
  component in run order ("Twelve components are registered…"); *Interfaces &
  integrations* has the third-party source table, which gains rows for the npm
  packages, the GitHub release tarball and `astral.sh`. Line-number anchors past
  the insertion points need re-anchoring.
- `docs/planning/CONVENTIONS.md` — only if a rule changes. Adding components
  does not change one; splitting `build-essential` into `bl_update`
  ([06](06-shell-essentials.md)) does not either.
- `.claude/CLAUDE.md` — the file map and the "Adding a new component" worked
  example. Unchanged unless the component contract changes.

# Options

- **A. Full checklist**: all components install and `check` green on a fresh
  Ubuntu 24.04 host in both root-only and created-user modes; the registry
  invariant test passes; README table and SPECS.md updated in the same commit.
- **B. Root-only mode only** — the documented primary use case; halves the
  verification effort.
- **C. Local only** — tests pass, docs updated, no real-host run.

# Recommendation

**A**, with the second host run reduced to a spot check. Concretely:

1. `bash tests/test_vps_boot.sh` — 33 cases pass (32 existing + the registry
   invariant).
2. On a fresh Ubuntu 24.04 VPS, root-only mode, QuickStart: every new component
   installs and `vps-boot.sh check` reports `✓` for all of them, exit 0.
3. Spot-check created-user mode: `install` completes, and the new components
   resolve on `PATH` **as the created user** — this is where `java`'s
   `/etc/profile.d/java.sh` and `uv`'s `/usr/local/bin` pinning either work or
   don't, and it is the failure mode `install_herdr`'s comment exists to warn
   about.
4. Version output is real, not `?`, in every new `check_*` — a `?` means the
   version probe is wrong even though the binary is present.
5. `README.md` toolchain table and `SPECS.md` (component list, count,
   third-party source table, line anchors) updated in the same commit as the
   code.

# Verdict

**A.** Accepted at triage, with the created-user run as a spot check.

1. `bash tests/test_vps_boot.sh` — 33 cases pass (32 existing + the registry
   invariant from [11](11-verification.md)).
2. Fresh Ubuntu 24.04, root-only, **Full install**: all 23 components install
   and `vps-boot.sh check` reports `✓` for each, exit 0.
3. Spot-check created-user mode: the new components resolve on `PATH` **as the
   created user** — where `java`'s and `rust`'s `/etc/profile.d` drop-ins and
   `uv`'s pinned install dir either work or don't.
4. Every new `check_*` prints a real version, never `?`.
5. `README.md` toolchain table and `SPECS.md` (component list, count,
   third-party source table, line anchors) updated in the same commit.

Added at triage, from the surfaces this change grew:

6. The wizard renders correctly at 23 components on an **80×24** terminal — the
   regression [14](14-quickstart-scope.md) exists to fix. Check the picker, the
   collapse summary and the Confirm screen.
7. `check_caddy` reports the UFW state, not just the service state
   ([18](18-caddy.md)).
8. `check` surfaces unattended-upgrades and `/var/run/reboot-required`
   ([19](19-unattended-upgrades.md)).
9. `check_claude` gains a real version string ([20](20-version-audit.md)).
