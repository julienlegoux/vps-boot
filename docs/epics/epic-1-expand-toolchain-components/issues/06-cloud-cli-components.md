---
type: Issue
title: "Add the vercel, hostinger and neon CLIs"
description: "Populate the cloud group with two npm CLIs and the Hostinger CLI, installed from a checksum-verified GitHub release tarball."
tags: [epic-1]
timestamp: 2026-08-17T13:30:00Z
epic: 1
issue: 06
slug: cloud-cli-components
size: S
status: in-progress
gh_issue: 24
depends_on: [1]
resource: https://github.com/julienlegoux/vps-boot/issues/24
---

# Add the vercel, hostinger and neon CLIs

## Summary

The `cloud` group, which has no members until this issue. Two of the three are
one-line npm installs; `hostinger` is the only new component that fetches a
release tarball, and it carries the checksum verification that makes doing so
acceptable.

## Scope

Three triples in the Components section, `cloud` group, `COMPONENT_DEFAULT` 1,
`COMPONENT_SCOPE` `system`, registered after the `agents` group and before
`infra` — and after `node`, which `vercel` and `neon` need.

**`vercel`** — `npm install -g vercel`. Sign-in hint must say
`vercel login --no-browser`: bare `vercel login` waits on a browser callback and
hangs on a headless box.

**`neon`** — `npm install -g neonctl`. The package name and the binary name
differ: `check_neon` probes **`neonctl`**, not the second binary name `neon`.
Getting this wrong produces a check that passes or fails for the wrong reason,
so make the choice explicit in a comment.

**`hostinger`** — a GitHub releases tarball into `/usr/local/bin`, mirroring
`install_go` (`vps-boot.sh:659-668`) in structure:

- Resolve the latest tag from the GitHub releases API rather than pinning.
- Map `dpkg --print-architecture` to the asset's architecture naming.
- **Verify `checksums.sha256`** against the downloaded asset before installing
  it, and fail the step if it does not match. This is the one new component
  fetching an unsigned binary; the checksum is the reason it is in scope at all.
  `install_go` does not do this, so there is no in-repo pattern to copy — write
  it, and let `set -euo pipefail` surface the mismatch rather than handling it.
- Sign-in hint: note that the Hostinger token is **account-wide** — the same
  credential that lists a VPS can rebuild it.

Each `check_*` prints a real version string. Plus rows in `README.md`'s toolchain
table (`README.md:37-52`) and a row in `docs/planning/SPECS.md`'s third-party
source table — `hostinger` is a new row there alongside `go` and `herdr` as a
non-apt, non-npm source. The component roster and count at `SPECS.md:49-50`
are reconciled once, in issue 09 — this PR does not touch that sentence.

## Out of scope

- **Writing any token or credential to disk during the run.** Out on the merits,
  not just scope: a Hostinger token that can rebuild a VPS is its own change. The
  sign-in hint tells the operator what to run after the install; the script never
  stores a secret.
- Pinning `hostinger` to a fixed release. Resolving newest-at-install-time is the
  epic's decided approach and the audit is the evidence it has cost nothing.
- `wrangler`, `AWS CLI`, `Terraform`, `tailscale` — considered and excluded.
- A fallback when the GitHub API is rate-limited or the asset naming changes. The
  step fails loudly, which is the intended behaviour.
- Re-anchoring SPECS.md's line numbers past the moved blocks. The reorder
  shifts them, and every following issue shifts them again; the sweep is
  issue 09.

## Acceptance criteria / Definition of done

- [ ] `bash tests/test_vps_boot.sh` passes, registry-invariant case included.
- [ ] `bash -n vps-boot.sh` is clean.
- [ ] `vercel` and `neon` `register` lines appear after `register node` in file
      order (`grep -n '^register ' vps-boot.sh`).
- [ ] On a fresh Ubuntu 24.04 host with all three selected: `vercel --version`,
      `hostinger --version` and `neonctl --version` each print a version, and
      `/usr/local/bin/hostinger` is executable.
- [ ] The checksum path is proven, not assumed: temporarily corrupt the
      downloaded asset (or point the check at a wrong file) and confirm the step
      fails with `✗` and a log tail, rather than installing a bad binary. Revert
      before opening the PR.
- [ ] `check_neon` probes `neonctl`; `grep -n 'neonctl' vps-boot.sh` shows it in
      both the install and the check.
- [ ] `vps-boot.sh check` prints a real version for all three, never `?`.
- [ ] The `vercel` sign-in hint contains `--no-browser`, and the `hostinger` hint
      states the token is account-wide.
- [ ] `README.md`'s toolchain rows and `docs/planning/SPECS.md`'s third-party
      source table row updated in the same commit; the roster and count at
      `SPECS.md:49-50` are issue 09's.

## Relevant files / areas

- `vps-boot.sh:659-668` — `install_go`, the tarball/arch idiom `hostinger`
  mirrors (minus the checksum, which is new).
- `vps-boot.sh:515-530` — `install_node`, the positional dependency.
- `vps-boot.sh:579-580`, `:597-598`, `:710-711` — existing sign-in hint phrasing
  and column alignment.
- `README.md:37-52` (toolchain table); `docs/planning/SPECS.md` (third-party
  source table — the roster and count at `SPECS.md:49-50` are issue 09's).
- `docs/planning/changes/change-1-expand-toolchain-components/02-vercel-cli.md`,
  `03-hostinger-cli.md`, `17-neon-cli.md`.

## Dependencies

- **Blocked by**: issue 01.
- **Blocks**: nothing.

## PR size note

If this grows past ~1000, split it before opening the PR. Expect ~130, with
`hostinger` roughly half of it.
