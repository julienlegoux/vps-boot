---
type: Decision
title: "Rust"
description: "Add a Rust toolchain via rustup, installed system-wide."
tags: [decision, change]
timestamp: 2026-08-16T09:05:00Z
phase: change
decision: 16
slug: rust
status: decided
verdict: "A - rustup pinned system-wide with -y --no-modify-path"
decided_via: triage
depends_on: [approach]
change: 1
change_slug: expand-toolchain-components
---

# Question

Pulled back in from [09-considered-and-excluded](09-considered-and-excluded.md)
at the user's request. Rust joins `go`, `python` and `java` as a fourth language
toolchain.

`rustup` is the only sane install path, but its default behaviour is wrong for
this box in three specific ways:

- it installs into `$HOME/.cargo` and `$HOME/.rustup` — per-user, so a
  root-mode install leaves nothing for a created user, and vice versa;
- it appends a `PATH` line to the user's shell rc files;
- run bare, it is **interactive** — it prints a menu and waits. Inside
  `step_run`, that hangs the run with no visible cause.

All three are fixed by the same invocation the official `rust` container images
use:

```
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
  | RUSTUP_HOME=/usr/local/rustup CARGO_HOME=/usr/local/cargo \
    sh -s -- -y --no-modify-path
```

then a `/etc/profile.d/rust.sh` exporting `CARGO_HOME`/`RUSTUP_HOME` and adding
`/usr/local/cargo/bin` to `PATH`. This is the `install_go` /
`install_herdr` pattern combined: pin the install directory system-wide, drop a
profile file, never touch a user's rc.

One hard dependency: **`cargo` needs a linker.** `cc` comes from
`build-essential`, which today is only present as a Hermes side effect
([06](06-shell-essentials.md)). A `rust` component on a box without
`build-essential` installs fine and then fails on the first `cargo build`.

# Options

- **A. `rustup` pinned system-wide** as above, `system` scope, profile drop-in.
- **B. `apt install rustc cargo`** — Ubuntu's Rust, no `rustup`, so no toolchain
  switching, no `stable`/`nightly`, and a version that lags. Wrong tool for a
  dev box.
- **C. Per-user rustup** (`user` scope, like `hermes`) — matches upstream's
  intent but leaves root-only boxes, which are the documented primary mode,
  without Rust on `PATH`.

# Recommendation

**A.** `-y --no-modify-path` plus pinned `RUSTUP_HOME`/`CARGO_HOME` is the
established containerised-Rust recipe and it removes the interactivity that
would otherwise hang `step_run`.

`check_rust` should report both `rustc --version` and `cargo --version` — a
half-installed toolchain where `cargo` is missing is the failure worth catching.

The `build-essential` dependency makes [06](06-shell-essentials.md)'s
recommendation (put it in `bl_update`) load-bearing rather than merely tidy: if
that is rejected, this component needs its own `apt install -y build-essential`
line, and the epic must say so.

# Verdict

**A.** Accepted at triage.

`rustup` with `-y --no-modify-path` and `RUSTUP_HOME=/usr/local/rustup`
`CARGO_HOME=/usr/local/cargo` — the containerised-Rust recipe, which also
removes the interactive menu that would hang `step_run`. Plus
`/etc/profile.d/rust.sh` for the env vars and `/usr/local/cargo/bin` on `PATH`.
`system` scope, `languages` group. `check_rust` reports both `rustc` and
`cargo`.

Depends on [06](06-shell-essentials.md)'s verdict: `cargo` needs `cc` from
`build-essential`, now in `bl_update`.
