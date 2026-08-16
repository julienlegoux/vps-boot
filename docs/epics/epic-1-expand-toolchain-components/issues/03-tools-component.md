---
type: Issue
title: "Add the tools component (jq, ripgrep, fd, htop, tree)"
description: "Register a core-group tools component that apt-installs the CLI essentials and exposes fd-find's fdfind binary as fd via update-alternatives."
tags: [epic-1]
timestamp: 2026-08-17T14:30:00Z
epic: 1
issue: 03
slug: tools-component
size: S
status: in-progress
gh_issue: 21
depends_on: [1]
resource: https://github.com/julienlegoux/vps-boot/issues/21
---

# Add the tools component (jq, ripgrep, fd, htop, tree)

## Summary

The CLI utilities every session on this box reaches for within a minute, bundled
as one component rather than five. It registers in the `core` group and — the
non-obvious part — **before `hermes`**: the Hermes installer offers to install
`ripgrep` when it is missing, and a prompt inside a `step_run` body hangs the run
with no visible cause, because stdout is redirected to the log. Having `ripgrep`
already present is what stops that prompt firing.

## Scope

- Add an `install_tools` / `check_tools` / `register tools …` triple in the
  Components section, in the `core` group, positioned after `sudo_nopasswd` and
  before `docker`.
- `install_tools` runs a single `apt install -y jq ripgrep fd-find htop tree`
  (`apt`, never `apt-get` — see CONVENTIONS.md), then exposes `fd`:
  `fd-find` installs its binary as **`fdfind`** on Debian/Ubuntu, so add an
  `update-alternatives --install /usr/local/bin/fd fd /usr/bin/fdfind …` link.
  Mirror the idiom `install_python` already uses for `python`
  (`vps-boot.sh:601-656`). Leave a comment explaining *why* the alternative
  exists — the name collision is exactly the kind of workaround the next reader
  would otherwise "clean up".
- `check_tools` must print a real version string, not just a presence test —
  report the versions of the five binaries (or a compact roll-up), and `ko` when
  any is missing. `fd` must be probed under the name `fd`, since that link is
  half of what this component delivers.
- Register with `COMPONENT_DEFAULT` 1, `COMPONENT_SCOPE` `system`, group `core`,
  no sign-in hint.
- Add a row to `README.md`'s toolchain table (`README.md:37-52`) and a row to
  `docs/planning/SPECS.md`'s third-party source table under Interfaces. The
  component roster and count at `SPECS.md:49-50` are reconciled once, in
  issue 09 — this PR does not touch that sentence.

## Out of scope

- `build-essential` — it goes into `bl_update` in issue 02, not here. If issue 02
  has not merged yet, do not compensate by adding it to this component.
- Any tool outside the five listed. `bat`, `eza`, `zoxide` and friends were not
  part of the decision.
- Replacing `/usr/bin/fdfind` or diverting the Debian binary. The alternative
  adds a name; it does not repoint the distro's.
- Re-anchoring SPECS.md's line numbers past the moved blocks. The reorder
  shifts them, and every following issue shifts them again; the sweep is
  issue 09.

## Acceptance criteria / Definition of done

- [ ] `bash tests/test_vps_boot.sh` passes, including the registry-invariant case
      from issue 01 — which is what proves the new triple's three names agree.
- [ ] `bash -n vps-boot.sh` is clean.
- [ ] The `register tools` line sits before the `register hermes` line in file
      order; verify with `grep -n '^register ' vps-boot.sh` and read the
      sequence.
- [ ] On a fresh Ubuntu 24.04 host with `tools` selected: `command -v fd` resolves
      and `fd --version` prints a version, and `jq`, `rg`, `htop`, `tree` all
      resolve on `PATH`.
- [ ] `vps-boot.sh check` prints a `✓` line for the component carrying real
      version numbers — never `?`.
- [ ] Also verify as the created user in created-user mode: `/usr/local/bin` is
      on the default `PATH`, so `fd` must resolve there too.
- [ ] `README.md`'s toolchain row and `docs/planning/SPECS.md`'s third-party
      source table row updated in the same commit; the roster and count at
      `SPECS.md:49-50` are issue 09's.

## Relevant files / areas

- `vps-boot.sh:411-731` — Components section; insert after the `sudo_nopasswd`
  block (`:415-446`).
- `vps-boot.sh:601-656` — `install_python` / `check_python`, the
  `update-alternatives` idiom to copy.
- `vps-boot.sh:683-711` — `install_hermes`, the reason position matters.
- `README.md:37-52` — toolchain table.
- `docs/planning/SPECS.md` — third-party source table under Interfaces, the
  row this PR owns. The roster and count at `SPECS.md:49-50` are issue 09's
  to reconcile.

## Dependencies

- **Blocked by**: issue 01 — `register` takes a group argument only after it.
- **Blocks**: nothing.

## PR size note

If this grows past ~1000, split it before opening the PR. This one should land
around 60.
