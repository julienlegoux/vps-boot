---
type: Issue
title: "Add the codex, gemini and pi agent CLIs"
description: "Register three npm-installed coding agents in the agents group and give check_claude the version string it is the only existing check to lack."
tags: [epic-1]
timestamp: 2026-08-17T13:15:00Z
epic: 1
issue: 05
slug: agent-cli-components
size: S
status: in-progress
gh_issue: 23
depends_on: [1]
resource: https://github.com/julienlegoux/vps-boot/issues/23
---

# Add the codex, gemini and pi agent CLIs

## Summary

Three more coding agents alongside `claude` and `opencode`, all installed the
same way — `npm install -g` — which is why they are one PR. The `agents` group
goes from three members to six.

The one hazard is `pi`: its documented install path is `pi.dev/install.sh`, a
wrapper that **prompts for a `PATH` edit**. A prompt inside a `step_run` body
hangs the run with no visible cause, because stdout is redirected to the log. The
npm package is the install path here, deliberately.

This issue also carries the version-audit fix for `check_claude`, since it is a
three-line change to the neighbouring block in the same group and would be noise
as its own PR.

## Scope

Three triples in the Components section, `agents` group, each with
`COMPONENT_DEFAULT` 1, `COMPONENT_SCOPE` `system`, registered **after `node`** —
the ordering that makes `npm -g` work is positional and nothing enforces it:

| Key | Package | Notes |
|---|---|---|
| `codex` | `@openai/codex` | |
| `gemini` | `@google/gemini-cli` | |
| `pi` | `@earendil-works/pi-coding-agent` | **not** `pi.dev/install.sh` — leave a comment saying why |

Placed in the `agents` group after `opencode` and before `hermes`, following the
epic's group order (`claude`, `opencode`, `codex`, `gemini`, `pi`, `hermes`).

Each `check_*` prints a real version string, following the `check_opencode`
shape (`vps-boot.sh:587-595`). Each `register` line carries a sign-in hint in the
8th argument, since all three need post-install auth — match the phrasing style
of the existing hints at `vps-boot.sh:580` and `:598`.

**`check_claude` fix** (`vps-boot.sh:571-577`): it is the only one of the twelve
existing checks that reports no version. Give it the same
`claude --version | head -1 | awk '{print $NF}'` treatment the sibling checks use,
so it prints `claude <version>` rather than `claude code installed`.

Plus rows in `README.md`'s toolchain table (`README.md:37-52`) and a row in
`docs/planning/SPECS.md`'s third-party source table — the npm row there
currently lists four packages and becomes seven. The component roster and
count at `SPECS.md:49-50` are reconciled once, in issue 09 — this PR does not
touch that sentence.

## Out of scope

- `hermes`' hardcoded sudoers path (`vps-boot.sh:687`, `:690`) — a known
  deviation, explicitly out of the epic even though this issue registers next to
  it.
- A Node version guard. Investigated and dropped: `pi` has the highest
  `engines.node` floor at ≥22.19 against NodeSource Active LTS 24.19.0, and three
  existing defences make the failure mode unreachable. Do not add one.
- Any agent beyond these three. Others were considered and excluded.
- Provisioning API keys or tokens for the agents — out on the merits, not just
  scope. The sign-in hints tell the operator what to run; the script never writes
  a credential.
- Re-anchoring SPECS.md's line numbers past the moved blocks. The reorder
  shifts them, and every following issue shifts them again; the sweep is
  issue 09.

## Acceptance criteria / Definition of done

- [ ] `bash tests/test_vps_boot.sh` passes, registry-invariant case included.
- [ ] `bash -n vps-boot.sh` is clean.
- [ ] All three `register` lines appear **after** `register node` in file order —
      check with `grep -n '^register ' vps-boot.sh`.
- [ ] `grep -n 'pi\.dev' vps-boot.sh` returns nothing.
- [ ] On a fresh Ubuntu 24.04 host with all three selected: `codex --version`,
      `gemini --version` and `pi --version` each print a version, and the install
      run completes without stalling on any step (the `pi` step in particular).
- [ ] `vps-boot.sh check` prints a real version for all three **and for
      `claude`** — no `?` anywhere in the component block.
- [ ] The `do_check` footer lists a sign-in hint for each of the three; confirm
      the "Sign in:" block renders them without breaking the rail
      (`vps-boot.sh:1469-1481`).
- [ ] `README.md`'s toolchain rows and `docs/planning/SPECS.md`'s third-party
      source table row updated in the same commit; the roster and count at
      `SPECS.md:49-50` are issue 09's.

## Relevant files / areas

- `vps-boot.sh:566-598` — the `claude` and `opencode` blocks: the shape to copy,
  and the `check_claude` fix.
- `vps-boot.sh:515-530` — `install_node`; the dependency the position encodes.
- `vps-boot.sh:1469-1481` — the sign-in hint footer in `do_check`.
- `README.md:37-52` (toolchain table); `docs/planning/SPECS.md` (third-party
  source table, npm row — the roster and count at `SPECS.md:49-50` are
  issue 09's).
- `docs/planning/changes/change-1-expand-toolchain-components/04-pi-coding-agent.md`
  and `08-additional-agent-clis.md`.

## Dependencies

- **Blocked by**: issue 01.
- **Blocks**: nothing.

## PR size note

If this grows past ~1000, split it before opening the PR. Expect ~110.
