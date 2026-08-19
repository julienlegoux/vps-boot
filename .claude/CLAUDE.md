# vps-boot — Claude memory

Single-file bash bootstrap for fresh Ubuntu LTS VPSes. `vps-boot.sh install` runs an interactive wizard; `vps-boot.sh harden` re-runs SSH key enrollment + lockdown; `vps-boot.sh check` re-runs the verifier. Distributed via `curl … | sudo bash`.

## File map

`vps-boot.sh` is read top to bottom:

1. **Header & `set -euo pipefail`**
2. **Constants** — port range, log path, APT lock timeout, sudoers/sshd/state paths (`STATE_FILE` = components, `STATE_CONFIG` = account + port), `REMOTE_URL`, the system-wide `RUSTUP_HOME_DIR` / `CARGO_HOME_DIR` (all env-overridable for tests), ANSI colors
3. **UI library** — `term_cols` / `term_lines` / `vis_len`, `banner`, `section`, `rail`, `body`, `done_section`, `step_run`, `ok` / `ko` / `note`, `die`, `warn`, `prompt_text`, `prompt_password`, `prompt_radio`, and the grouped grid picker (`prompt_multiselect` plus its `msel_*` helpers). All reads go through `< /dev/tty` so `curl | sudo bash` works.
4. **Component registry** — `COMPONENT_GROUPS` (the six group names, in order) + `register()` + parallel associative arrays (`COMPONENT_NAME`, `COMPONENT_DESC`, `COMPONENT_DEFAULT`, `COMPONENT_SCOPE`, `COMPONENT_GROUP`, `COMPONENT_INSTALL`, `COMPONENT_CHECK`, `COMPONENT_SIGNIN`)
5. **Components** — one block per tool (`install_xxx`, `check_xxx`, `register xxx …`), laid out under one `# ══ <group> ══` banner per group. Order = run order.
6. **Baseline** — `bl_update`, `bl_unattended`, `bl_user`, `bl_ufw`, `bl_ssh_harden`, `bl_fail2ban`. Mandatory, NOT registered, always run in this order. Plus the `set_sshd` helper, the sshd policy predicates (`sshd_effective_value`, `sshd_root_is_key_only`, `hardening_is_applied`, …), and the apt/dpkg lock helpers `wait_for_apt` (called before every `apt update`/`apt upgrade`/`apt install` in the script) and `stop_apt_timers`/`restore_apt_timers` (neutralise `apt-daily(-upgrade).timer` for the duration of `cmd_install`, restored via the `cmd_install_cleanup` EXIT trap even on failure).
7. **State** — `write_state_config` / `read_state_config`
8. **SSH key enrollment** — `harden_command`, `enroll_ssh_key`
9. **Validation** — `valid_username`, `valid_port`, `random_port`
10. **Flows** — `cmd_install`, `cmd_harden` (+ `harden_resolve_target`, `harden_report`), `cmd_check`, `do_check` (+ `do_check_footer`), `cmd_help`
11. **Entry point** — `main "$@"` at the bottom

## Adding a new component (worked example: btop)

Three things, all in the **Components** section, inside the group banner the component belongs to (`core`, `languages`, `packaging`, `agents`, `cloud`, `infra` — the six values of `COMPONENT_GROUPS`, in that order):

```bash
# ══ core ══════════════════════════════════════════════════
# ─── btop ─────────────────────────────────────────────────
install_btop() {
  apt install -y btop
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

register btop "btop" "process viewer" 1 system core install_btop check_btop
#        ^id  ^name  ^short-desc      ^default-on (1=yes)
#                                       ^scope (system|user)
#                                              ^group (one of COMPONENT_GROUPS)
#                                                   ^install fn  ^check fn

# All eight arguments above are required — `register` dies on fewer, so a
# component can never end up with an empty group.
#
# Optional 9th arg: a short sign-in hint shown in the do_check footer
# (only set this for components that need post-install auth, e.g. gh/claude):
#   register btop "btop" "process viewer" 1 system core install_btop check_btop "btop login (opens browser)"
```

That's it. The wizard's Custom picker places it in its group's row automatically, the `Full install` label's count and per-group counts follow from the registry, and `cmd_check` runs `check_btop`. No other plumbing.

One thing the registry does *not* update: the toolchain table in `README.md`. Add the row there too, under the same group and in registry order — `test_readme_lists_every_component_in_registry_order` fails until you do.

## Conventions

- **Output**: use `section`, `rail`, `body`, `step_run`, `ok`, `ko`, `note`, `die`, `warn` — never raw `echo`/`printf` for user-visible text. The visual style stays consistent if every line goes through the helpers.
- **Widths**: read the terminal through `term_cols` / `term_lines`, never `tput` directly, and measure any string that might hold a glyph with `vis_len` — `${#s}` counts *bytes* under the C locale and every glyph here is multi-byte. Never declare a local named `width`: `term_cols` is resolved dynamically, so a same-named local shadows what a caller (or a test stub) set.
- **Never join an unbounded list into one line.** A wrapped line loses its rail prefix and breaks the left border. `selection_summary` is the bounded renderer both summary surfaces use — *both* of its branches, the full selection included: with six groups the group-count form is 76 columns against the Confirm screen's 67-column budget.
- **Version parsing**: never guess a tool's `--version` format, and never let `|| echo "?"` stand in for a real value — a `?` inside an `ok` is a green tick over something unverified. Run the command on a real host, paste the verbatim first line into a test stub, and parse against that. The formats that have already bitten: `openjdk version "25.0.3" 2026-04-21` (two `grep -o` matches, the date lands on a second, rail-less line), `2.1.233 (Claude Code)` (`$NF` is `Code)`), `tree v2.1.1 © 1996 - 2023 by Steve Baker, …` (a whole copyright notice), `Hermes Agent v0.20.2 (…)`, and rustup's shims, which need `RUSTUP_HOME` exported or they cannot name a toolchain at all.
- **Reads**: every prompt redirects from `/dev/tty`. Direct `read` without that redirect breaks under `curl | sudo bash`.
- **apt calls**: call `wait_for_apt` immediately before every `apt update`/`apt upgrade`/`apt install`, including inside a component's `install_xxx`. `DPkg::Lock::Timeout` (the `99-vps-boot-lock-timeout` fragment) only bounds dpkg's own lock wait — it does nothing for the apt lists lock that `apt update` takes first, which is what let issue #43 through when `apt-daily.timer` fired mid-install.
- **Errors**: `die "<msg>"` only for unrecoverable preconditions (wrong UID, bad args). Inside `install_xxx` functions, let `set -euo pipefail` handle failures — `step_run` captures the exit code, prints ✗, and dumps the last 15 log lines.
- **Idempotency**: `install_xxx` should detect "already installed" and short-circuit when reasonable. The baseline (`bl_user` in particular) is NOT idempotent — re-running install with the same username will fail at `useradd`. Re-runs of `install` are not a supported path in this round. `cmd_harden` is the deliberate exception and must stay idempotent: it is the supported recovery path, so nothing in it may assume a first run.
- **Scope**: register with `system` for steps that run as root (most apt-based installs), `user` for steps that need to run as `$USERNAME` (nvm, bun, claude). For user-scope work inside an install fn, use:
  ```bash
  sudo -u "$USERNAME" -H bash <<'EOF'
  set -eo pipefail
  cd "$HOME" || exit 1   # NOT optional — see below
  ...
  EOF
  ```
  **`cd "$HOME"` is mandatory, not tidiness.** `-H` sets `HOME` but leaves the working directory where the caller was, and the caller is root sitting in `/root` — mode `700`, unreadable to `$USERNAME`. Anything the step runs that touches `.` then fails as the unprivileged user. This is invisible in root-only mode (where the user *is* root) and only shows up on a created-user install, which is why it survived eight PRs: the created-user acceptance run died on `install_hermes` with `error: failed to query metadata of symlink /root/.venv: Permission denied (os error 13)` after 22 of 23 components had installed cleanly. uv probes `.` for `uv.toml` and `.venv`; other installers probe for other things. The same applies to `check_*` functions that shell out as the user.
- **Logging**: `step_run` redirects each step's stdout+stderr to `/tmp/vps-boot.log`. On failure it dumps the tail. Don't print to stdout from inside install fns — it'll mess up the line-rewrite.
- **State**: two files under `/etc/vps-boot/`.
  - `components` — the enabled component keys, one per line, written by `cmd_install`. `cmd_check` reads it on standalone runs so it only checks what was actually installed. If the file is missing (legacy install / first standalone run after a manual setup), it falls back to checking every registered component.
  - `config` — `USERNAME=` / `SSH_PORT=`, written by `write_state_config` **immediately after the `bl_ssh_harden` step**, not at the end of the run. That placement is the point: the enrollment prompt after it waits on a human and dies on SIGHUP, and `harden` has to be able to resolve its target on the next connection. `cmd_check` and `cmd_harden` both default to it, with argv overriding.
- **Hardening is a command, not a phase**: `cmd_harden` (`vps-boot.sh harden [username]`) runs `enroll_ssh_key` + `lockdown_ssh` standalone and idempotently; `cmd_install` reaches the same `enroll_ssh_key` inline. Two rules to preserve:
  - **`harden` takes no port argument.** It resolves the port from recorded state → the managed drop-in → `sshd -T`. A mistyped port would be written into the drop-in as `Port` and move the listener off the port the operator is connected through.
  - **Locked-down state is derived from `sshd -T` (`hardening_is_applied`), never from a marker file.** The drop-in gets hand-edited during lockout recovery, and a marker that disagrees with the running daemon is worse than no marker.
  Any user-visible "you are not hardened yet" text names `$(harden_command)`, which falls back to the `curl … | sudo bash -s harden` form because `$0` is `bash` under a piped run.
- **Optional user creation**: the wizard's first prompt is "User account" — defaults to `skip` (everything runs as root) since the primary use case is autonomous AI environments where sudo prompts are pure friction. When skipped, `USERNAME=root`, `bl_user` is not run, `install_docker` skips the group add (root already has socket access), and `bl_ssh_harden` keeps `PermitRootLogin yes` during install (so `ssh-copy-id root@…` still works) then `enroll_ssh_key` tightens it to `prohibit-password` after lockdown. Component checks branch on `$USERNAME == "root"`.

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
