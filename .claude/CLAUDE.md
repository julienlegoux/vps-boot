# vps-boot — Claude memory

Single-file bash bootstrap for fresh Ubuntu LTS VPSes. `vps-boot.sh install` runs an interactive wizard; `vps-boot.sh check` re-runs the verifier. Distributed via `curl … | sudo bash`.

## File map

`vps-boot.sh` is read top to bottom:

1. **Header & `set -euo pipefail`**
2. **Constants** — `NVM_VERSION`, port range, log path, ANSI colors
3. **UI library** — `banner`, `section`, `rail`, `body`, `done_section`, `step_run`, `ok` / `ko` / `note`, `die`, `warn`, `prompt_text`, `prompt_password`, `prompt_radio`, `prompt_multiselect`. All reads go through `< /dev/tty` so `curl | sudo bash` works.
4. **Component registry** — `register()` + parallel associative arrays (`COMPONENT_NAME`, `COMPONENT_DESC`, `COMPONENT_DEFAULT`, `COMPONENT_SCOPE`, `COMPONENT_INSTALL`, `COMPONENT_CHECK`, `COMPONENT_SIGNIN`)
5. **Components** — one block per tool (`install_xxx`, `check_xxx`, `register xxx …`). Order = run order.
6. **Baseline** — `bl_update`, `bl_user`, `bl_ufw`, `bl_ssh_harden`, `bl_fail2ban`. Mandatory, NOT registered, always run in this order. Plus the `set_sshd` helper.
7. **SSH key enrollment** — `enroll_ssh_key`
8. **Validation** — `valid_username`, `valid_port`, `random_port`
9. **Flows** — `cmd_install`, `cmd_check`, `do_check`, `cmd_help`
10. **Entry point** — `main "$@"` at the bottom

## Adding a new component (worked example: btop)

Three things, all in the **Components** section, between the existing component blocks:

```bash
# ─── btop ─────────────────────────────────────────────────
install_btop() {
  apt-get install -y btop
}

check_btop() {
  if command -v btop >/dev/null 2>&1; then
    local v
    v=$(btop --version 2>/dev/null | head -1 | awk '{print $NF}' || echo "?")
    ok "btop $v"
  else
    ko "btop not installed"
  fi
}

register btop "btop" "process viewer" 1 system install_btop check_btop
#        ^id  ^name  ^short-desc      ^default-on (1=yes)
#                                       ^scope (system|user)
#                                                ^install fn  ^check fn

# Optional 8th arg: a short sign-in hint shown in the do_check footer
# (only set this for components that need post-install auth, e.g. gh/claude):
#   register btop "btop" "process viewer" 1 system install_btop check_btop "btop login (opens browser)"
```

That's it. The wizard's Custom multi-select picks it up automatically. `cmd_check` runs `check_btop` automatically. No other plumbing.

## Conventions

- **Output**: use `section`, `rail`, `body`, `step_run`, `ok`, `ko`, `note`, `die`, `warn` — never raw `echo`/`printf` for user-visible text. The visual style stays consistent if every line goes through the helpers.
- **Reads**: every prompt redirects from `/dev/tty`. Direct `read` without that redirect breaks under `curl | sudo bash`.
- **Errors**: `die "<msg>"` only for unrecoverable preconditions (wrong UID, bad args). Inside `install_xxx` functions, let `set -euo pipefail` handle failures — `step_run` captures the exit code, prints ✗, and dumps the last 15 log lines.
- **Idempotency**: `install_xxx` should detect "already installed" and short-circuit when reasonable. The baseline (`bl_user` in particular) is NOT idempotent — re-running install with the same username will fail at `useradd`. Re-runs are not a supported path in this round.
- **Scope**: register with `system` for steps that run as root (most apt-based installs), `user` for steps that need to run as `$USERNAME` (nvm, bun, claude). For user-scope work inside an install fn, use:
  ```bash
  sudo -u "$USERNAME" -H bash <<'EOF'
  set -eo pipefail
  ...
  EOF
  ```
- **Logging**: `step_run` redirects each step's stdout+stderr to `/tmp/vps-boot.log`. On failure it dumps the tail. Don't print to stdout from inside install fns — it'll mess up the line-rewrite.
- **State**: `cmd_install` writes the enabled component keys (one per line) to `/etc/vps-boot/components`. `cmd_check` reads it on standalone runs so it only checks what was actually installed. If the file is missing (legacy install / first standalone run after a manual setup), it falls back to checking every registered component.

## Visual vocabulary

| Glyph | Meaning |
|-------|---------|
| `◇`   | open / pending section |
| `◆`   | completed / active section |
| `│`   | left rail (connects sections) |
| `●` / `○` | radio (single-select) |
| `◉` / `◌` | checkbox (multi-select) |
| `›`   | text input cursor |
| `✓`   | success status |
| `✗`   | failure status |
| `!`   | warning status |

Colors: orange section titles · dim hints and rails · green ✓ · red ✗ · yellow ! · cyan accents (cursor, hyperlinks, key paths).

The ASCII banner (block letters spelling `VPS-BOOT`) is hardcoded as a heredoc inside `banner()`. To rebrand, replace the heredoc — no runtime `figlet` dependency.
