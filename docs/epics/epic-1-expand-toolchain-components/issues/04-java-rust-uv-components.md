---
type: Issue
title: "Add the java, rust and uv components"
description: "Add the newest-LTS JDK, a system-wide non-interactive rustup install, and uv — the three additions that need PATH or environment plumbing outside their own install directory."
tags: [epic-1]
timestamp: 2026-08-17T11:00:00Z
epic: 1
issue: 04
slug: java-rust-uv-components
size: S
status: open
gh_issue: 22
depends_on: [1]
resource: https://github.com/julienlegoux/vps-boot/issues/22
---

# Add the java, rust and uv components

## Summary

The three new components that are not "install a binary and be done": each one
has to make itself resolvable for both root and a created user, through a
`/etc/profile.d` drop-in or a pinned install directory. They are grouped into one
PR because that plumbing is the reviewable substance and it is the same problem
three times — not because they are three unrelated tools that happen to be next
in the list.

Two of the three also carry an interactive-installer hazard: bare `rustup` shows
a menu, and a prompt inside a `step_run` body hangs the run silently, because
stdout is redirected to the log.

## Scope

Three triples in the Components section, each with `COMPONENT_DEFAULT` 1,
`COMPONENT_SCOPE` `system`, and no sign-in hint:

**`java`** — group `languages`, registered after `go`.

- Probe for the newest **installable LTS** JDK: iterate LTS majors descending
  and take the first `openjdk-NN-jdk-headless` that `apt install --dry-run`
  accepts. LTS majors are exactly those where `(NN - 21) % 4 == 0` — 17, 21, 25,
  29, 33 — since the four-release (two-year) LTS cadence starting at 17. The
  filter needs no bumping in 2027, which is the point of expressing it as a rule
  rather than a list.
- This is **not** `default-jdk` (21 on noble, one LTS behind) and **not** simply
  the newest `openjdk-NN` the archive offers. Those happen to coincide at 25 on
  noble today only because Ubuntu backported LTS JDKs alone into noble; that is
  backport policy, not a guarantee, and Ubuntu does package feature releases in
  interim distros. Leave the reasoning as a comment — a six-month feature release
  on an unattended box is the failure this filter prevents.
- Write `/etc/profile.d/java.sh` exporting `JAVA_HOME`, mirroring
  `install_go`'s drop-in (`vps-boot.sh:659-668`), `chmod 644`.
- `check_java` must redirect `2>&1` when reading the version (`java -version`
  writes to stderr) and must assert **`javac`**, not just `java` — a JRE-only
  box would otherwise pass.

**`rust`** — group `languages`, registered after `java`.

- Install via `rustup` with `-y --no-modify-path`, `RUSTUP_HOME=/usr/local/rustup`
  and `CARGO_HOME=/usr/local/cargo`, plus `/etc/profile.d/rust.sh` putting
  `/usr/local/cargo/bin` on `PATH`. Bare `rustup` is interactive; the flags are
  what keep `step_run` from hanging. Comment the reason.
- `check_rust` reports `rustc` and `cargo` versions.

**`uv`** — group `packaging`, registered after `pnpm`.

- Install from `astral.sh/uv/install.sh` with `UV_INSTALL_DIR=/usr/local/bin`.
  This mirrors `install_herdr`'s pinned-directory fix (`vps-boot.sh:714-719`):
  upstream defaults into `$HOME/.local/bin`, which is not on `PATH` for a fresh
  root-only box.
- `check_uv` reports the `uv` version.

Plus: rows in `README.md`'s toolchain table (`README.md:37-52`), and rows in
`docs/planning/SPECS.md`'s third-party source table. The component roster and
count at `SPECS.md:49-50` are reconciled once, in issue 09 — this PR does not
touch that sentence.

## Out of scope

- `python` itself and the deadsnakes path — unchanged; `uv` sits beside it, it
  does not replace it.
- `mise` / `asdf` / any version manager, and `sdkman` for Java — considered and
  excluded by the epic.
- Repointing `/usr/bin/python3` or any distro interpreter, for the same reason
  `install_python` deliberately does not.
- Installing a Rust toolchain component set beyond the default (`clippy`,
  `rustfmt` come with the default profile; nothing extra is added).
- Re-anchoring SPECS.md's line numbers past the moved blocks. The reorder
  shifts them, and every following issue shifts them again; the sweep is
  issue 09.

## Acceptance criteria / Definition of done

- [ ] `bash tests/test_vps_boot.sh` passes, registry-invariant case included.
- [ ] `bash -n vps-boot.sh` is clean.
- [ ] On a fresh Ubuntu 24.04 host, root-only mode, all three selected:
      `java -version` and `javac -version` both print **25** (the newest LTS on
      noble today), `rustc --version` and `cargo --version` print versions, and
      `uv --version` prints a version.
- [ ] `echo $JAVA_HOME` in a **fresh login shell** is non-empty and points at the
      installed JDK; `command -v cargo` resolves in that same fresh shell. A drop-in
      that only works after a manual `source` does not pass.
- [ ] Created-user mode spot check: all three resolve **as the created user** in
      a fresh login shell — this is where the `/etc/profile.d` drop-ins and `uv`'s
      pinned directory either work or do not.
- [ ] `vps-boot.sh check` prints a real version for each of the three, never `?`.
- [ ] The LTS filter is exercised, not assumed: confirm the probe rejects a
      non-LTS major. `apt install --dry-run openjdk-24-jdk-headless` fails on
      noble, so also confirm by reading the loop that 22/23/24/26 are never
      probed at all.
- [ ] `README.md`'s toolchain rows and `docs/planning/SPECS.md`'s third-party
      source table rows updated in the same commit; the roster and count at
      `SPECS.md:49-50` are issue 09's.

## Relevant files / areas

- `vps-boot.sh:411-731` — Components section; `java` and `rust` after the `go`
  block (`:658-680`), `uv` after the `pnpm` block (`:550-564`). Both positions
  are as of issue 01's reorder, not the current file.
- `vps-boot.sh:601-656` — `install_python`, the `apt install --dry-run` probing
  idiom `java` borrows. Note the epic's warning: this idiom transplanted badly
  and needed two corrections, because for `go` and `python` "default", "newest"
  and "newest LTS" collapse into one version and for Java they do not.
- `vps-boot.sh:659-668` — `install_go`, the `/etc/profile.d` drop-in pattern.
- `vps-boot.sh:714-719` — `install_herdr`, the pinned-install-dir pattern.
- `README.md:37-52` (toolchain table); `docs/planning/SPECS.md` (third-party
  source table under Interfaces — the roster and count at `SPECS.md:49-50`
  are issue 09's).
- `docs/planning/changes/change-1-expand-toolchain-components/05-java-jdk.md` —
  keeps both superseded verdicts as history; read it before changing the filter.
- Also: `16-rust.md`, `07-uv.md` in the same ledger.

## Dependencies

- **Blocked by**: issue 01.
- **Blocks**: nothing.

## PR size note

If this grows past ~1000, split it before opening the PR. Expect ~150. If the
Java probe alone turns into a large block, splitting `java` out from `rust` +
`uv` is the natural cut.
