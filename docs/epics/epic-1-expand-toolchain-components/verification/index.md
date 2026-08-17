# Verification — Epic 1: Expand the toolchain component registry

Evidence from the epic's acceptance runs against a real, freshly rebuilt
Ubuntu 24.04.4 LTS host. The wizard is interactive and reads through
`/dev/tty`, so every run was driven inside a tmux pane sized `80x24` and
captured with `tmux pipe-pane` / `script(1)`; ANSI escapes are stripped in the
saved files.

* [run-1-root-full-install.txt](./run-1-root-full-install.txt) - run 1 transcript: root-only mode, Full install, 22 applicable components, every step ✓
* [run-1-root-full-check.txt](./run-1-root-full-check.txt) - run 1 standalone `vps-boot.sh check root 24617`: 37 passed, 0 failed, 1 warning, exit 0, no `?`
* [run-1-wizard-80x24.md](./run-1-wizard-80x24.md) - run 1 rendering at 80×24: picker, collapse summary and Confirm screen, before and after the `selection_summary` fix
