---
type: Decision
title: "Shell essentials and build toolchain"
description: "The audit's biggest gap: no build-essential, no jq, no ripgrep on a box meant for autonomous agents."
tags: [decision, change]
timestamp: 2026-08-16T09:05:00Z
phase: change
decision: 06
slug: shell-essentials
status: decided
verdict: "C - build-essential into bl_update; jq, ripgrep, fd-find, htop, tree into a tools component"
decided_via: triage
depends_on: [approach]
change: 1
change_slug: expand-toolchain-components
---

# Question

Part of "what else is missing". This one is not a preference — the audit turned
up a functional gap.

`bl_update` (`vps-boot.sh:766-772`) installs exactly: `wget gnupg lsb-release
ca-certificates software-properties-common ufw fail2ban git unzip curl sudo`.

**One component does install a compiler, accidentally.** Reading
`NousResearch/hermes-agent`'s `install.sh` — the script `install_hermes`
(`vps-boot.sh:683-698`) pipes to `bash` — it runs
`apt-get install -y -qq build-essential python3-dev libffi-dev` unconditionally,
and offers `ripgrep` + `ffmpeg` behind a user confirmation. So on a QuickStart
box today, `gcc` and `make` are present *because Hermes was ticked*, and
unticking Hermes silently removes the compiler from the machine. Nothing states
that dependency anywhere; nothing tests it.

That is an argument **for** this decision, not against it. So the provisioned
box has:

- **no `build-essential` of its own** — no `gcc`, no `make`, no headers, except
  as Hermes' side effect above. Any `npm -g` package with a native addon
  (`node-gyp`), any `pip install` of a package without a wheel for the
  deadsnakes interpreter, and `cargo` if Rust is ever added, all fail at compile
  time on a box where Hermes was unticked. The four npm components installed
  today happen to be pure JS, so the gap is invisible until the operator
  installs their own dependency — which is the whole point of the box.
- **no `jq`** — every shell script that touches a JSON API needs it, including
  the `hostinger` and `gh` workflows this change is adding.
- **no `ripgrep` / `fd-find`** — the standard search tools agents reach for.
  Claude Code bundles its own `rg`, but `opencode`, `pi` and `hermes` shell out
  to whatever is on `PATH`. Hermes' installer knows this and offers to install
  `ripgrep` itself — behind an interactive confirmation, which is a prompt
  sitting inside a `step_run` body. Installing `ripgrep` before Hermes runs
  removes that prompt's reason to fire.
- **no `htop`/`btop`, no `tree`, no `ncdu`** — pure convenience, cheap.

All of these are single apt packages in main. Note `fd-find` installs the binary
as `fdfind` on Debian/Ubuntu, not `fd`; exposing `fd` needs an
`update-alternatives` line or a symlink.

The structural question is *where* they go: `bl_update`'s mandatory base list,
or a registered, toggleable component.

# Options

- **A. New `tools` component** — `build-essential jq ripgrep fd-find htop tree`
  in one registered block, default on, toggleable in Custom mode. Follows the
  registry convention; an operator who wants a minimal box can uncheck it.
- **B. Append to `bl_update`'s base package list** — treats a compiler as
  baseline rather than optional. Arguably correct for `build-essential`, since
  other components' *own* installers can fail without it, but the baseline is
  deliberately minimal and not toggleable.
- **C. Split** — `build-essential` into `bl_update` (it is a dependency of other
  components, not a user convenience), the rest into a `tools` component.
- **D. Skip** — leave it to the operator.

# Recommendation

**C**, and the Hermes finding is what settles it. The dependency already exists
— `build-essential` is already being installed on most boxes — it is just
undeclared, invisible, and attached to an unrelated component that an operator
is free to untick. Moving it into `bl_update` does not add a package to the
typical install; it makes an accidental guarantee into a real one, and removes a
failure mode that is currently silent.

The rest (`jq ripgrep fd-find htop tree`) is operator convenience, belongs in a
toggleable `tools` component, and should include the `fd` alternatives line so
the binary answers to its documented name. Ordering it before `hermes` also
pre-empts that installer's interactive `ripgrep` prompt.

If the preference is to keep `bl_update` untouched, **A** is the fallback — but
then the epic should note that unticking both `tools` and `hermes` yields a box
with no compiler.

# Verdict

**C.** Accepted at triage.

`build-essential` moves into `bl_update`'s base package list — making an
accidental guarantee (it arrives today only as a Hermes side effect) into a real
one. `jq ripgrep fd-find htop tree` become a registered `tools` component in the
`core` group, including the `update-alternatives` line that exposes `fdfind` as
`fd`.

`tools` registers early, before `hermes`, which also pre-empts that installer's
interactive `ripgrep` prompt. [16](16-rust.md) depends on this verdict: `cargo`
needs a linker.
