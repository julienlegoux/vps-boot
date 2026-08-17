---
type: Decision
title: "pi coding agent"
description: "Install pi.dev through its upstream install.sh or straight from npm?"
tags: [decision, change]
timestamp: 2026-08-16T09:05:00Z
phase: change
decision: 04
slug: pi-coding-agent
status: decided
verdict: "A - npm install -g @earendil-works/pi-coding-agent, bypassing the upstream wrapper"
decided_via: triage
depends_on: [approach]
change: 1
change_slug: expand-toolchain-components
---

# Question

`pi.dev` is a minimal open-source terminal coding agent (MIT, no SaaS backend,
15+ model providers including local ones) — a sibling to the `claude`, `opencode`
and `hermes` components already registered. Binary name `pi`.

The advertised install is `curl -fsSL https://pi.dev/install.sh | sh`. Reading
that script changes the picture: it is a 42KB wrapper whose real job is to
install the npm package `@earendil-works/pi-coding-agent`. It detects an npm
global prefix, falls back to `$HOME/.local` when that is not writable, may shell
out to `apt`/`apk` to obtain Node, and **prompts** to append a `PATH` line to
`~/.bashrc` / `~/.zshrc` / `~/.profile`.

That prompt is the problem. `install_*` bodies run with stdout redirected to
`/tmp/vps-boot.log` and must not write to stdout at all (`CONVENTIONS.md`), and
an installer that blocks on an interactive question inside `step_run` hangs the
run with no visible cause. `install_herdr` (`vps-boot.sh:714-719`) hit the
adjacent version of this problem — an upstream default of `$HOME/.local/bin`,
not on `PATH` for a fresh root-only box — and solved it by pinning
`HERDR_INSTALL_DIR`.

Version facts: latest is `0.84.2`, `bin` is `pi` → `dist/cli.js`, no `os`/`cpu`
restrictions, `engines.node >= 22.19.0`. The `node` component installs current
LTS via NodeSource `setup_lts.x`, which is comfortably past that floor.

# Options

- **A. `npm install -g @earendil-works/pi-coding-agent`** — skips the wrapper
  entirely, identical to `install_claude` / `install_opencode`, no prompt, no
  `PATH` edit, lands in the same global prefix as the other four npm tools.
- **B. `curl … | sh` with `PI_NPM_INSTALL_PREFIX=/usr/local`** — follows the
  documented path, but keeps the interactive `PATH` prompt and the Node
  auto-install branch, both of which are wrong for this context.
- **C. Skip pi** — three agents are already installed.

# Recommendation

**A.** The wrapper's entire value is bootstrapping Node and fixing `PATH`, and
this script has already done both by the time the component runs. Going direct
to npm removes the only two behaviours that would break `step_run`. Register
`system` scope after `node`, `check_pi` shaped like `check_opencode`
(`pi --version`), sign-in hint `pi` then `/login` and `/model` — pi's auth is an
in-app slash command, not a CLI subcommand, which is worth stating in the hint.

Risk to note in the epic: the package name is not the command name, so a rename
upstream would break silently. Worth a comment on the install line naming
`pi.dev` as the source of truth.

# Verdict

**A.** Accepted at triage.

`npm install -g @earendil-works/pi-coding-agent`, bypassing `pi.dev/install.sh`
entirely — the wrapper's only jobs are bootstrapping Node and fixing `PATH`,
both already done by the time the component runs, and its interactive `PATH`
prompt would hang `step_run`. `system` scope, `agents` group. `check_pi` on
`pi --version`. Sign-in hint: run `pi`, then `/login` and `/model` — auth is an
in-app slash command, not a CLI subcommand.

Carry into the epic: the package name is not the command name, so the install
line needs a comment naming `pi.dev` as the source of truth.
