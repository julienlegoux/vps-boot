---
type: Decision
title: "apt vs apt-get in install functions"
description: "The script mixes apt-get and apt; which is canonical for new component install functions?"
tags: [decision, mapping]
timestamp: 2026-08-07T00:33:16Z
phase: mapping
decision: 02
slug: apt-vs-apt-get
status: decided
verdict: "apt everywhere — always use apt; existing apt-get call sites are replaced via a tracked issue"
decided_via: discussion
depends_on: []
---

# Question

`vps-boot.sh` calls the package manager two different ways. `apt-get` appears 11
times — the baseline (`bl_update`), `install_docker`, `install_gh`,
`install_python` — and `apt` appears twice, in `install_node` (`vps-boot.sh:517`)
and `install_tmux` (`vps-boot.sh:680`).

The split is chronological rather than random: `apt` appears in the two most
recently added component blocks, while every older block uses `apt-get`. The
checked-in `.claude/CLAUDE.md` worked example (the "adding a component" contract
new components are written against) still shows `apt-get install -y btop`, so the
documented contract points the opposite way from the newest code.

`apt-get` has the stable, script-safe CLI; `apt` prints an "unstable CLI
interface" warning under non-interactive use, though in practice with
`DEBIAN_FRONTEND=noninteractive` exported (`vps-boot.sh:1229`) and all step output
redirected to the log, that warning is invisible.

# Options

- **`apt` for new install functions, leave existing `apt-get` calls alone** —
  matches the newest code; the divergence stays, bounded and intentional.
- **`apt-get` everywhere** — matches the documented contract in `CLAUDE.md` and
  the majority of the code; requires converting the two `apt` calls back.
- **`apt` everywhere** — one style, but a bulk rewrite of 11 working call sites in
  the security-critical baseline for no functional gain.

# Recommendation

**`apt` for new install functions, leaving the existing `apt-get` calls
untouched**, and update the `CLAUDE.md` worked example to match so the contract
stops contradicting the code. This is the direction the last two components
already took, and a bulk rewrite of the baseline's package calls carries risk
without benefit. `CONVENTIONS.md` should record the rule as forward-looking rather
than describing the file as uniformly one style, because it is not.

# Verdict

**`apt` everywhere.** `apt` is the package-manager command for this project,
without exception — new install functions and existing code alike. The convention
is unconditional, not forward-looking.

The ten existing `apt-get` call sites are not left in place: replacing them is
tracked as its own change rather than folded into this mapping run. Those sites
are `install_docker` (`vps-boot.sh:460-461`), `install_gh` (`:497-498`),
`install_python` (`:568`, `:577`, `:586`) and the baseline `bl_update`
(`:729-731`). The `.claude/CLAUDE.md` worked example, which still teaches
`apt-get install -y btop`, is part of the same change — left as is, it keeps
producing new components in the wrong style.

`apt-cache search` (`:574`) is out of scope: `apt search` is a different command
with different output, not a drop-in replacement.

This overrides the recommendation above, which favoured leaving the existing
`apt-get` calls untouched.

## Follow-through

Completed on 2026-08-16. Commit `ba7a29b` (`refactor: replace every apt-get call
with apt`) converted all ten call sites and updated the `.claude/CLAUDE.md` worked
example to `apt install -y btop`. No `apt-get` invocation remains in the repo — the
only textual match left is a comment at `vps-boot.sh:684` describing the upstream
Hermes installer's own `apt-get`, which this project does not control.
`apt-cache search` (`vps-boot.sh:609`) stays as scoped out above. Issue #16 is
closed.

Line references in the Verdict are as of `50c133b` and have since shifted.
