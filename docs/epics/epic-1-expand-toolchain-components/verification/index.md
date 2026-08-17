# Verification — Epic 1: Expand the toolchain component registry

Evidence from the epic's acceptance runs against a real, freshly rebuilt
Ubuntu 24.04.4 LTS host. The wizard is interactive and reads through
`/dev/tty`, so every run was driven inside a tmux pane sized `80x24` and
captured with `tmux pipe-pane` / `script(1)`; ANSI escapes are stripped in the
saved files.

* [run-1-root-full-install.txt](./run-1-root-full-install.txt) - run 1 transcript: root-only mode, Full install, 22 applicable components, every step ✓
* [run-1-root-full-check.txt](./run-1-root-full-check.txt) - run 1 standalone `vps-boot.sh check root 24617`: 37 passed, 0 failed, 1 warning, exit 0, no `?`
* [run-1-wizard-80x24.md](./run-1-wizard-80x24.md) - run 1 rendering at 80×24: picker, collapse summary and Confirm screen, before and after the `selection_summary` fix
* [run-2-created-user-notes.md](./run-2-created-user-notes.md) - run 2 walkthrough: the created user, all 23 offered, the Hermes CWD failure and how the run was completed without a second `install`
* [run-2-created-user-install.txt](./run-2-created-user-install.txt) - run 2 transcript: 22 of 23 ✓ then `Hermes ✗` with the uv `Permission denied` error
* [run-2-created-user-check.txt](./run-2-created-user-check.txt) - run 2 `check devuser 38030`: 39 passed, 0 failed, 1 warning, exit 0, all 23 components, no `?`
* [run-2-created-user-login-shell.txt](./run-2-created-user-login-shell.txt) - run 2 `bash -l` as `devuser`: `java`, `javac`, `cargo`, `uv`, `fd`, `go`, `rustc` and every CLI resolving off `/etc/profile.d`
