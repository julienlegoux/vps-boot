---
type: Decision
title: "Version audit"
description: "Does any existing component install a stale version, the way the Java recommendation nearly did?"
tags: [decision, change]
timestamp: 2026-08-16T09:35:00Z
phase: change
decision: 20
slug: version-audit
status: decided
verdict: "A - record the audit and fix check_claude; no Node guard, no version pinning"
decided_via: triage
depends_on: [java-jdk]
change: 1
change_slug: expand-toolchain-components
---

# Question

Raised by the user after the Java correction: if the first recommendation
shipped Java 21 when 25 is the LTS, is anything *already in the script* equally
stale?

The Java near-miss had a specific cause worth naming, because it is what makes
the question answerable rather than open-ended: that recommendation tracked
**the distro's default** (`default-jdk` → 21) instead of **the newest available**
(`openjdk-25` in noble's `universe`). Every other component resolves its version
by one of four mechanisms, none of which is "the distro default".

Audit of all twelve existing components, versions checked 2026-08-16:

| Component | Mechanism | Resolves to today | Stale? |
|---|---|---|---|
| `docker` | vendor apt repo, `stable` | latest CE | no |
| `gh` | vendor apt repo, `stable` | latest | no |
| `node` | NodeSource `setup_lts.x` | **24.19.0** (Krypton, Active LTS) | no — Current is 26.7.0, but tracking Active LTS is the stated intent |
| `bun` | `npm -g bun` | latest published | no |
| `pnpm` | `npm -g pnpm` | latest published | no |
| `claude` | `npm -g @anthropic-ai/claude-code` | **2.1.233** | no |
| `opencode` | `npm -g opencode-ai` | latest published | no |
| `python` | probes deadsnakes with `apt --dry-run`, newest first | newest installable `python3.X` | no — this is the self-correcting idiom |
| `go` | `go.dev/VERSION?m=text` | **go1.26.6** | no |
| `hermes` | vendor `install.sh` | latest | no |
| `herdr` | vendor `install.sh`, dir pinned | latest | no |
| `sudo_nopasswd` | n/a | — | — |

**Nothing is stale, and nothing is version-pinned.** The Java case was the only
instance of the distro-default trap, and it was caught before it shipped —
because Java is the only tool in the set whose apt metapackage points at
something older than what the archive carries.

Two real findings did fall out of the pass:

1. **`check_claude` reports no version.** It prints `ok "claude code installed"`
   (`vps-boot.sh:571-577`) — the only check of the twelve that does not report a
   version string. Every other one uses `--version`. So the one component whose
   currency matters most on this box is the one the verifier cannot speak about.
2. **Node's floor is satisfied, and — after reading the actual installer — it
   is already well defended.** This item was investigated twice; the second pass
   reversed the conclusion of the first, so both are recorded.

   Nine components install through `npm -g`. Each declares a minimum Node
   version in `engines.node`: `pi` ≥22.19 (the highest), `claude` ≥22.0,
   `neonctl` ≥20.19, `gemini` ≥20, `codex` ≥16. NodeSource's Active LTS is
   24.19.0, so all nine clear their floor.

   **What a too-old Node would do.** npm's `engine-strict` defaults to `false`,
   so a Node below a package's floor produces an `EBADENGINE` **warning** and
   npm installs anyway, **exiting 0**. `step_run` would print `✓`, the warning
   would go to `/tmp/vps-boot.log` (only shown on failure), and the breakage
   would surface later at runtime. That failure mode is genuinely silent, which
   is what first argued for an explicit guard.

   **But it cannot be reached.** Reading `deb.nodesource.com/setup_lts.x` as
   served today, three independent things prevent it:

   - The script carries `NODE_VERSION="24.x"` **hardcoded**, and NodeSource
     bumps that file when the Active LTS moves. So `install_node` gets the
     current LTS at the moment it runs, and Active LTS only ever moves
     *forward* — 24 → 26 → 28. The floor (22.19) gets further away over time,
     never closer.
   - The script's `handle_error` **exits non-zero** on every failure path
     (unsupported architecture, failed `apt update`, failed keyring write). It
     is the last command in `install_node`'s pipeline under `set -euo pipefail`,
     so a failed setup fails the step rather than passing silently.
   - It writes an apt pin — `Package: nodejs` / `Pin: origin deb.nodesource.com`
     / `Pin-Priority: 600` — so even with the repo half-configured, `apt install
     nodejs` cannot quietly fall back to Ubuntu noble's own `nodejs`
     (18.19.1, universe), which *is* below every floor. That fallback was the
     one plausible route to a silently-too-old Node, and it is blocked.

   The residual risk is a NodeSource lag *forward* — a few weeks on 24 after 26
   becomes LTS in October 2026. Harmless.

# Options

- **A. Record the audit, fix `check_claude`, add nothing else.** The version
  story is healthy; the one gap is a missing version string.
- **B. A, plus one guard on the Node version.** A constant for the highest
  declared floor (`NODE_MIN_MAJOR=22`), checked in `install_node` right after
  the install — so a lagging NodeSource stops the run at the step named "Node
  LTS", with a message naming the real problem, instead of producing nine
  green-but-broken components. Roughly:

  ```bash
  local major
  major=$(node --version); major=${major#v}; major=${major%%.*}
  (( major >= NODE_MIN_MAJOR )) || {
    printf 'ERROR: node %s is below the minimum %s required by the npm components\n' \
      "$major" "$NODE_MIN_MAJOR" >&2
    return 1
  }
  ```

  Ten lines, one constant to keep honest, and it converts a silent runtime
  failure into a named install failure.
- **C. A + B, plus pin versions** for reproducibility. Reverses the project's
  existing "always newest" stance and contradicts
  [12-scope-boundary](12-scope-boundary.md).

# Recommendation

**A** — record the audit, fix `check_claude`, add no guard.

The headline stands: there is nothing stale to fix. The "always resolve newest
at install time" convention is doing its job across all twelve components, and
the Java trap does not generalise, because Java was the only one resolving
against a distro *default* rather than the newest available. Recording that is
worth more than changing anything — it tells the next person asking this
question that it has been asked, and how the answer was reached.

`check_claude` should print `claude --version` like its eleven siblings. One
line; folds into [13](13-acceptance-criteria.md) item 4.

**On the Node guard, this doc changed its mind twice, and the reasoning is worth
keeping visible:**

1. First pass: optional rider, on the assumption a stale Node would fail loudly.
2. Second: promoted to recommended, on discovering npm's `engine-strict`
   defaults to false — the failure would be silent.
3. Third, after reading `setup_lts.x` itself rather than reasoning about it: the
   silent path is unreachable. Active LTS only moves forward, the installer
   exits non-zero on every failure path, and its apt pin blocks the fallback to
   Ubuntu's `nodejs` 18.19.1 that was the one realistic route to a too-old
   interpreter.

A guard against a failure mode with three independent existing defences is not
worth a constant that has to be kept in sync with nine packages' `engines`
fields — that constant is itself a thing that goes stale. The guard is dropped.

What survives from the investigation is the **documentation**: the Node
dependency of nine components, and the reason it is safe, belong in the epic's
Notes so the next person does not re-derive them.

**C is out** — pinning is already recorded as out of scope
([12](12-scope-boundary.md)), and this audit is the evidence that not pinning
has cost nothing so far.

# Verdict

**A.** Accepted at triage.

The audit stands as the deliverable: all twelve existing components resolve to
current versions, nothing is stale, and the distro-default trap that nearly
shipped a Java 21 was unique to Java.

One code change: `check_claude` prints `claude --version` like its eleven
siblings.

No Node guard — three existing defences make its failure mode unreachable, and
the constant it would need is itself a staleness risk. No version pinning.

The Node dependency of the nine `npm -g` components, and why it is safe, go into
the epic's Notes.
