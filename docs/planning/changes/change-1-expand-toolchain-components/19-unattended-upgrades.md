---
type: Decision
title: "Unattended upgrades"
description: "Automatic security updates — a baseline step, not a component."
tags: [decision, change]
timestamp: 2026-08-16T09:05:00Z
phase: change
decision: 19
slug: unattended-upgrades
status: decided
verdict: "A - new bl_unattended baseline step, Automatic-Reboot left false"
decided_via: triage
depends_on: []
change: 1
change_slug: expand-toolchain-components
---

# Question

Pulled back in from [09-considered-and-excluded](09-considered-and-excluded.md)
at the user's request. Unlike the other three repêchages, this one is **not a
component** — it is hardening, and hardening is the baseline's job
(`bl_update`, `bl_ufw`, `bl_ssh_harden`, `bl_fail2ban`), which is mandatory and
deliberately not registered.

That placement matters here more than usual: a box provisioned by this script is
meant to be left running unattended (the stated use case is autonomous AI
environments). A host that never applies security updates is exactly the host
that should not be left alone, and making that protection a checkbox someone can
untick defeats the point.

Facts:

- Ubuntu Server images generally ship `unattended-upgrades` installed and
  enabled for the security pocket, but this is image-dependent and the script
  currently asserts nothing about it. `bl_update` does a one-shot
  `apt update && apt upgrade` and never revisits.
- Configuration lives in `/etc/apt/apt.conf.d/` — `20auto-upgrades` (the
  enable switch) and `50unattended-upgrades` (what gets upgraded, whether to
  auto-reboot). The script already owns a file in that directory,
  `99-vps-boot-lock-timeout` (`APT_LOCK_CONFIG`), so the pattern and the
  transactional-write convention are established.
- **Reboots are the sharp edge.** `Unattended-Upgrade::Automatic-Reboot "true"`
  will reboot the box unprompted, which on a machine running long agent sessions
  is destructive in a way a package upgrade is not. Default is `false`.
- There is an interaction with `APT_LOCK_CONFIG`: `SPECS.md` already records
  that background `unattended-upgrades` runs hold the dpkg lock, which is why
  the 180s `DPkg::Lock::Timeout` fragment exists. Enabling the timer makes that
  contention more likely on subsequent manual `apt` use, not less — the existing
  mitigation covers it, but the epic should not treat the two as unrelated.

# Options

- **A. New baseline step `bl_unattended`**, run after `bl_update`: install the
  package, write `20auto-upgrades` enabling security updates, leave
  `Automatic-Reboot` at `false`. Verified by a `check` entry.
- **B. Assert-and-report only** — don't configure anything, just have `do_check`
  report whether unattended-upgrades is active, leaving the fix to the operator.
- **C. As A, plus `Automatic-Reboot "true"` with a fixed reboot time.** Fully
  hands-off patching, at the cost of a box that can vanish mid-session.
- **D. Make it a registered, toggleable component.** Consistent with how
  everything optional works, inconsistent with it being security hardening.

# Recommendation

**A**, explicitly with `Automatic-Reboot` left `false`.

Security updates applied automatically is the right default for an unattended
box; rebooting it automatically is not, and the two are separable. Kernel
updates will accumulate needing a reboot — that is what the verifier is for:
`check` should surface `/var/run/reboot-required` as a `note`, so the operator
sees "reboot pending" in the same output they already read, and chooses when.

Rejecting **D** on the same reasoning as `build-essential`
([06](06-shell-essentials.md)): the baseline exists so that the security
properties of the box do not depend on which checkboxes were ticked.

Scope note: this is the first change in this batch that adds a `bl_*` step
rather than a component, so it touches `cmd_install`'s hardcoded baseline
sequence (`vps-boot.sh:1269-1275`) and the `do_check` output — a slightly wider
blast radius than the rest, and worth its own issue.

# Verdict

**A.** Accepted at triage.

New baseline step `bl_unattended`, run after `bl_update`: install
`unattended-upgrades`, write `/etc/apt/apt.conf.d/20auto-upgrades` enabling the
security pocket, **leave `Automatic-Reboot` at `false`** — a box that reboots
itself mid-agent-session is destructive in a way a package upgrade is not.

`do_check` gains two entries: whether unattended-upgrades is active, and a
`note` when `/var/run/reboot-required` exists, so pending kernel reboots surface
in output the operator already reads and they choose the moment.

Not a component, for the same reason as `build-essential`
([06](06-shell-essentials.md)): the security properties of the box must not
depend on which checkboxes were ticked. This is the only item in change 1 that
touches `cmd_install`'s hardcoded baseline sequence
(`vps-boot.sh:1269-1275`), so it warrants its own issue.
