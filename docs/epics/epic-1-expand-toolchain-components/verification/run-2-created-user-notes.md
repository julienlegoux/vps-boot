# Run 2 — created-user mode, Full install

Host: Ubuntu 24.04.4 LTS at `69.62.108.65`, rebuilt from scratch between run 1
and run 2 (run 1's port `24617` went with the old disk). Wizard driven inside a
tmux pane sized `80x24`.

| | |
|---|---|
| Created user | `devuser` |
| SSH port | **38030** (randomised by the wizard) |
| Install mode | Full install |
| Components offered | **23** — `Full install` read `everything — 23 tools`, `core 4 · languages 5 · packaging 3 · agents 6 · cloud 3 · infra 2` |
| Confirm line | `all 23  ·  core 4 · languages 5 · packaging 3 · agents 6 · +2 more` — 79 columns, no wrap |

The `core 4` and the "23 tools" confirm the other half of the count that run 1
established: `sudo_nopasswd` *is* applicable once a user exists, so
created-user mode offers all 23 where root-only offers 22. See
`../drift/09-root-mode-offers-22-of-23.md`.

## The run failed at Hermes, 22 components in

```
│  ◆  pi .................................... ✓
│  ◆  Hermes ................................ ✗
│
│  step failed (exit 2) — last 15 lines from /tmp/vps-boot.log:
│  │ → Installing managed uv into /home/devuser/.hermes/bin ...
│  │ ✓ Managed uv installed (uv 0.12.5 (x86_64-unknown-linux-gnu))
│  │ → Python 3.11 not found, installing via uv...
│  │ Installed Python 3.11.16 in 1.31s
│  │ error: failed to query metadata of symlink `/root/.venv`: Permission denied (os error 13)
```

`install_hermes` runs its body through `sudo -u "$USERNAME" -H bash`. `-H` sets
`HOME`, but the *working directory* is inherited from the caller — root, sitting
in `/root`, mode `700`. So the user-scope shell starts in a directory `devuser`
cannot stat. The Hermes installer runs uv, uv probes `.` for `uv.toml` and
`.venv`, and it dies before it starts.

Reproduced directly on the host:

```
$ sudo stat -c '%a %U' /root
700 root

$ sudo bash -c 'cd /root && sudo -u devuser -H bash -c "pwd; ls -a . | head -2"'
/root
ls: cannot access '.': Permission denied

$ sudo bash -c 'cd /root   && sudo -u devuser -H .../uv python list'
error: failed to open file `/root/uv.toml`: Permission denied (os error 13)

$ sudo bash -c 'cd /home/devuser && sudo -u devuser -H .../uv python list'
graalpy-3.10.0-linux-x86_64-gnu   <download available>
```

Root-only mode never sees this — there the user *is* root — which is why it
survived eight PRs and a clean run 1. `hermes` is the only `user`-scope
component, so it is also the only step that could have surfaced it.

Fixed by beginning the user-scope body with `cd "$HOME" || exit 1`, and by
correcting the idiom in `.claude/CLAUDE.md` and `SPECS.md` — the documentation
is what produced the bug, since it showed the pattern without the `cd`.

## Completing the run without a second `install`

`step_run` is fail-fast, so the run stopped at Hermes: the five components
registered after it (`vercel`, `neon`, `hostinger`, `caddy`, `herdr`) never
ran, `/etc/vps-boot/components` was never written, and `enroll_ssh_key` and
`do_check` never executed. Re-running `install` on the same host is explicitly
unsupported (`bl_user` fails at `useradd`), and a rebuild would have thrown
away the failure evidence.

So the fixed script was deployed to the host and the interrupted work was
resumed function by function, in registry order, exactly as `cmd_install` would
have called it:

1. `install_hermes` with the fix → **exit 0**, `hermes` on `PATH`, version
   `v0.20.2`. This is the fix proved on the real host, against the real
   installer, in the environment that broke.
2. `install_vercel`, `install_neon`, `install_hostinger`, `install_caddy`,
   `install_herdr` → all exit 0.
3. `/etc/vps-boot/components` written from `full_install_keys` — 23 keys.
4. `enroll_ssh_key` → chose `ok`; lockdown applied (`PasswordAuthentication
   no`, `KbdInteractiveAuthentication no`), key auth for `devuser` still works.

An intermediate `check` run before step 2 is worth recording because it is a
clean negative control: it reported exactly five failures — `vercel`,
`neonctl`, `hostinger`, `caddy`, `herdr` — i.e. precisely the components after
`hermes` in the registry, and nothing else. Nothing before Hermes was damaged
by the abort.

## Final state

[`run-2-created-user-check.txt`](./run-2-created-user-check.txt) —
`vps-boot.sh check devuser 38030`:

**39 passed, 0 failed, 1 warning, exit 0.** Zero `?` anywhere. All 23
components report a real version, including `passwordless sudo enabled for
devuser` (the component root-only mode filters out), `rust 1.97.1 (cargo
1.97.1)` and `hermes v0.20.2`. The single warning is `check_caddy` noting that
UFW denies 80/443 — correct for a fresh install, raised with `note`, and the
run still exits 0.

## Fresh login shell as the created user

[`run-2-created-user-login-shell.txt`](./run-2-created-user-login-shell.txt) —
a new SSH session as `devuser` running `bash -l`, so `/etc/profile.d` is
sourced and nothing is inherited from root:

```
JAVA_HOME          : /usr/lib/jvm/java-25-openjdk-amd64
RUSTUP_HOME        : /usr/local/rustup
CARGO_HOME         : /usr/local/cargo
profile.d drop-ins : /etc/profile.d/go.sh /etc/profile.d/java.sh /etc/profile.d/rust.sh

  java     /usr/bin/java              openjdk version "25.0.3" 2026-04-21
  javac    /usr/bin/javac             javac 25.0.3
  cargo    /usr/local/cargo/bin/cargo cargo 1.97.1 (c980f4866 2026-06-30)
  uv       /usr/local/bin/uv          uv 0.12.5 (x86_64-unknown-linux-gnu)
  fd       /usr/local/bin/fd          fdfind 9.0.0
  go       /usr/local/go/bin/go       go version go1.26.6 linux/amd64
  rustc    /usr/local/cargo/bin/rustc rustc 1.97.1 (8bab26f4f 2026-07-14)
```

Every npm-installed CLI resolves too (`node`, `npm`, `bun`, `pnpm`, `claude`,
`opencode`, `codex`, `gemini`, `pi`, `vercel`, `neonctl`), as do `hostinger`,
`herdr`, `hermes` and the `tools` set. `sudo -n true` succeeds without a
prompt, and `id -nG` reads `devuser sudo docker`.

This is what issue 04's `/etc/profile.d` drop-ins and uv's pinned install dir
exist for, and it is the run that proves them: `uv` and `fd` resolve because
their installers were pinned to `/usr/local/bin` rather than
`$HOME/.local/bin`, `go` and `java` because of their drop-ins, and `cargo` /
`rustc` because `rust.sh` exports `RUSTUP_HOME` — without which the rustup
shims cannot name a toolchain at all, which is the same root cause as run 1's
`rust ? (cargo ?)`.
