# Reliable Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Ubuntu bootstrap fail fast, wait up to 180 seconds for package locks, enforce effective SSH key-only lockdown, support root-only installs, and offer passwordless sudo in QuickStart and Custom.

**Architecture:** Keep the project single-file and add small, testable helpers inside `vps-boot.sh`. Use environment-overridable paths only for filesystem isolation in tests, an owned OpenSSH drop-in for deterministic precedence, and the existing component registry for passwordless sudo. Add a dependency-free Bash regression runner in `tests/test_vps_boot.sh`.

**Tech Stack:** Bash 4+, Ubuntu LTS system tools (`apt-get`, OpenSSH, sudo/visudo, systemd), Git Bash for local regression execution.

## Global Constraints

- APT lock waiting is capped at exactly 180 seconds and proceeds immediately when the lock is released.
- `main` remains unchanged; implementation stays on `codex/reliable-bootstrap` until final merge into `develop`.
- The first wizard choice defaults to root-only (`USERNAME=root`); created-user mode remains available.
- Passwordless sudo is default-on in QuickStart and a checkbox in the existing Custom list, but is absent for root-only installs.
- SSH lockdown disables both `PasswordAuthentication` and `KbdInteractiveAuthentication`, then reloads `ssh.service`.
- User-visible output continues through the existing UI helpers; installer internals continue writing only to the step log.
- Direct prompt reads continue using `/dev/tty`.
- Re-running `install` with an existing created username remains unsupported.

---

### Task 1: Sourceable script and fail-fast step execution

**Files:**
- Create: `tests/test_vps_boot.sh`
- Modify: `vps-boot.sh:18-20,90-120,1153`

**Interfaces:**
- Consumes: existing `step_run <label> <command> [args...]` contract.
- Produces: `VPS_BOOT_LOG_FILE` path override for tests; sourcing `vps-boot.sh` no longer invokes `main`; `step_run` returns the first failing command's status.

- [ ] **Step 1: Write the failing source-safety test**

Create `tests/test_vps_boot.sh` with this initial runner:

```bash
#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT_DIR/vps-boot.sh"
PASS_COUNT=0
FAIL_COUNT=0

pass() { printf 'ok - %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'not ok - %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
run_test() {
  local label=$1
  shift
  local rc
  set +e
  ( "$@" )
  rc=$?
  set -e
  if (( rc == 0 )); then
    pass "$label"
  else
    fail "$label"
  fi
}

test_source_does_not_run_main() {
  local output
  output=$(bash -c 'script=$1; set -- --help; source "$script"; printf sourced' bash "$SCRIPT" 2>&1)
  [[ "$output" == "sourced" ]]
}

run_test "sourcing vps-boot.sh does not run main" test_source_does_not_run_main

printf '%s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
(( FAIL_COUNT == 0 ))
```

- [ ] **Step 2: Run the source-safety test and verify RED**

Run:

```powershell
& 'C:\Program Files\Git\bin\bash.exe' tests/test_vps_boot.sh
```

Expected: exit 1 with `not ok - sourcing vps-boot.sh does not run main`, because sourcing currently prints the help screen through `main "$@"`.

- [ ] **Step 3: Guard the entry point and make the log path testable**

Change the log constant and bottom-level call:

```bash
readonly LOG_FILE="${VPS_BOOT_LOG_FILE:-/tmp/vps-boot.log}"
```

```bash
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
```

- [ ] **Step 4: Run the source-safety test and verify GREEN**

Run the Step 2 command.

Expected: `1 passed, 0 failed` and exit 0.

- [ ] **Step 5: Add the failing fail-fast regression test**

Append setup after the initial variable declarations, source the script after the source-safety test function definition, and add this behavior test:

```bash
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
export VPS_BOOT_LOG_FILE="$TEST_ROOT/vps-boot.log"

source "$SCRIPT"

test_step_run_stops_at_first_failure() {
  local trace="$TEST_ROOT/step-trace" rc
  failing_step() {
    printf 'before\n' >> "$trace"
    ( exit 23 )
    printf 'after\n' >> "$trace"
  }

  step_run "Failing probe" failing_step >/dev/null 2>&1
  rc=$?

  [[ $rc -eq 23 ]] || return 1
  [[ $(cat "$trace") == "before" ]]
}
```

Register it with:

```bash
run_test "step_run stops at the first failure" test_step_run_stops_at_first_failure
```

`run_test` executes each case in a subshell so command stubs do not leak between cases. Each test explicitly returns failure rather than relying on inherited `errexit`.

- [ ] **Step 6: Run the fail-fast test and verify RED**

Run the Step 2 command.

Expected: source test passes, fail-fast test fails because the current `if "$@"` context suppresses `errexit` in `failing_step` and allows `after` to run.

- [ ] **Step 7: Execute steps in an errexit-enabled subshell**

Replace the command portion of `step_run` with this complete status-capture and rendering block:

```bash
  local rc had_errexit=0
  [[ $- == *e* ]] && had_errexit=1
  set +e
  (
    set -euo pipefail
    "$@"
  ) >>"$LOG_FILE" 2>&1
  rc=$?
  (( had_errexit )) && set -e

  if (( rc == 0 )); then
    printf '\r%s│%s  %s◆%s  %s ' "$C_DIM" "$C_RESET" "$C_GREEN" "$C_RESET" "$label"
    printf '%s%s%s ' "$C_DIM" "$dotstr" "$C_RESET"
    printf '%s✓%s\n' "$C_GREEN" "$C_RESET"
    return 0
  else
    printf '\r%s│%s  %s◆%s  %s ' "$C_DIM" "$C_RESET" "$C_RED" "$C_RESET" "$label"
    printf '%s%s%s ' "$C_DIM" "$dotstr" "$C_RESET"
    printf '%s✗%s\n' "$C_RED" "$C_RESET"
    body ""
    body "${C_RED}step failed (exit $rc) — last 15 lines from $LOG_FILE:${C_RESET}"
    tail -n 15 "$LOG_FILE" 2>/dev/null | sed "s|^|${C_DIM}│  ${C_RED}│ ${C_RESET}|" || true
    return "$rc"
  fi
```

Do not invoke the subshell in `if`, `while`, `until`, `&&`, `||`, or `!`; those contexts recreate the same Bash exception.

- [ ] **Step 8: Run Task 1 verification**

Run:

```powershell
& 'C:\Program Files\Git\bin\bash.exe' -n vps-boot.sh
& 'C:\Program Files\Git\bin\bash.exe' -n tests/test_vps_boot.sh
& 'C:\Program Files\Git\bin\bash.exe' tests/test_vps_boot.sh
```

Expected: both syntax checks exit 0; tests report `2 passed, 0 failed`.

- [ ] **Step 9: Commit Task 1**

```powershell
git add vps-boot.sh tests/test_vps_boot.sh
git commit -m "fix: preserve fail-fast step execution"
```

---

### Task 2: Temporary APT lock timeout

**Files:**
- Modify: `tests/test_vps_boot.sh`
- Modify: `vps-boot.sh:16-20,801-940`

**Interfaces:**
- Consumes: `cmd_install` run phase.
- Produces: `install_apt_lock_timeout`, `remove_apt_lock_timeout`, `APT_LOCK_TIMEOUT=180`, and `VPS_BOOT_APT_LOCK_CONFIG` test override.

- [ ] **Step 1: Write the failing APT fragment test**

Export the path before sourcing the script:

```bash
export VPS_BOOT_APT_LOCK_CONFIG="$TEST_ROOT/99-vps-boot-lock-timeout"
```

Add:

```bash
test_apt_lock_timeout_fragment() {
  install_apt_lock_timeout || return 1
  [[ -f "$VPS_BOOT_APT_LOCK_CONFIG" ]] || return 1
  [[ $(cat "$VPS_BOOT_APT_LOCK_CONFIG") == 'DPkg::Lock::Timeout "180";' ]] || return 1
  remove_apt_lock_timeout || return 1
  [[ ! -e "$VPS_BOOT_APT_LOCK_CONFIG" ]]
}
```

Register it with:

```bash
run_test "APT lock timeout fragment is temporary" test_apt_lock_timeout_fragment
```

- [ ] **Step 2: Run the test and verify RED**

Run the Task 1 test command.

Expected: exit 1 because `install_apt_lock_timeout` is undefined.

- [ ] **Step 3: Implement fragment setup and cleanup**

Add constants:

```bash
readonly APT_LOCK_TIMEOUT=180
readonly APT_LOCK_CONFIG="${VPS_BOOT_APT_LOCK_CONFIG:-/etc/apt/apt.conf.d/99-vps-boot-lock-timeout}"
```

Add baseline helpers before `bl_update`:

```bash
install_apt_lock_timeout() {
  install -d -m 0755 "$(dirname "$APT_LOCK_CONFIG")"
  printf 'DPkg::Lock::Timeout "%s";\n' "$APT_LOCK_TIMEOUT" > "$APT_LOCK_CONFIG"
  chmod 0644 "$APT_LOCK_CONFIG"
}

remove_apt_lock_timeout() {
  rm -f "$APT_LOCK_CONFIG"
}
```

In `cmd_install`, immediately before the Installing run phase:

```bash
  install_apt_lock_timeout
  trap remove_apt_lock_timeout EXIT
```

After `do_check` returns normally:

```bash
  remove_apt_lock_timeout
  trap - EXIT
```

The fragment lives in APT's standard parts directory so direct and child APT processes inherit the same timeout.

- [ ] **Step 4: Run Task 2 verification**

Run syntax checks and the full test script.

Expected: `3 passed, 0 failed`; fragment contains exactly 180 seconds and is removed.

- [ ] **Step 5: Commit Task 2**

```powershell
git add vps-boot.sh tests/test_vps_boot.sh
git commit -m "fix: wait for background apt locks"
```

---

### Task 3: Optional user creation and root-safe component behavior

**Files:**
- Modify: `tests/test_vps_boot.sh`
- Modify: `vps-boot.sh:401-433,639-644,665-775,801-940,971-1040,1111-1130`

**Interfaces:**
- Consumes: wizard `user_mode`, global `USERNAME`, existing registry order.
- Produces: `configure_user_mode <skip|create>`, `component_is_applicable <key>`, `add_docker_group_if_needed`; `CREATE_USER` is `0` or `1`.

- [ ] **Step 1: Write failing root-mode helper tests**

Add:

```bash
test_configure_user_mode_skip() {
  USERNAME=someone
  USER_PASSWORD=secret
  CREATE_USER=1
  configure_user_mode skip || return 1
  [[ $CREATE_USER -eq 0 ]] || return 1
  [[ $USERNAME == root ]] || return 1
  [[ -z $USER_PASSWORD ]]
}

test_configure_user_mode_create() {
  USERNAME=""
  USER_PASSWORD=""
  CREATE_USER=0
  configure_user_mode create || return 1
  [[ $CREATE_USER -eq 1 ]]
}

test_root_skips_docker_group_change() {
  local calls="$TEST_ROOT/usermod-calls"
  usermod() { printf '%s\n' "$*" >> "$calls"; }
  USERNAME=root
  add_docker_group_if_needed || return 1
  [[ ! -e $calls ]]
}
```

Register all three:

```bash
run_test "skip mode configures root" test_configure_user_mode_skip
run_test "create mode enables user creation" test_configure_user_mode_create
run_test "root skips Docker group mutation" test_root_skips_docker_group_change
```

- [ ] **Step 2: Run tests and verify RED**

Expected: the three tests fail with undefined helper functions.

- [ ] **Step 3: Implement the helpers**

Add near validation/flow helpers:

```bash
configure_user_mode() {
  case "$1" in
    skip)
      CREATE_USER=0
      USERNAME=root
      USER_PASSWORD=""
      ;;
    create)
      CREATE_USER=1
      ;;
    *)
      return 2
      ;;
  esac
}

component_is_applicable() {
  local key=$1
  [[ "$key" != "sudo_nopasswd" || "$USERNAME" != "root" ]]
}

add_docker_group_if_needed() {
  if [[ "$USERNAME" != "root" ]]; then
    usermod -aG docker "$USERNAME"
  fi
}
```

Replace Docker's direct `usermod` with `add_docker_group_if_needed`. In `check_docker`, skip group membership reporting for root and retain the existing check for created users.

- [ ] **Step 4: Integrate the User account prompt**

At the start of `cmd_install`, add the existing radio UI before username input:

```bash
  local user_mode
  prompt_radio "User account" user_mode \
    "skip|run everything as root (best for autonomous AI environments)" \
    "create|create a sudo user"
  configure_user_mode "$user_mode"
```

Only run username validation and `prompt_password` when `CREATE_USER == 1`. Only run `step_run "User $USERNAME" bl_user` when creating a user. Update About, Confirm, `cmd_help`, `cmd_check`, and `do_check` copy/branches to report root-only mode accurately.

When building both QuickStart defaults and Custom multi-select arguments, apply:

```bash
component_is_applicable "$key" || continue
```

- [ ] **Step 5: Add root-specific SSH intent without implementing the drop-in yet**

Until Task 5 replaces SSH configuration, preserve existing behavior with these values:

```bash
if [[ "$USERNAME" == "root" ]]; then
  set_sshd PermitRootLogin "yes"
else
  set_sshd PermitRootLogin "no"
fi
```

After successful enrollment, set root to `prohibit-password`. This intermediate change keeps Task 3 independently usable and is replaced by the owned drop-in in Task 5.

- [ ] **Step 6: Run Task 3 verification**

Run syntax checks and full tests.

Expected: `6 passed, 0 failed` and no Docker group command for root.

- [ ] **Step 7: Commit Task 3**

```powershell
git add vps-boot.sh tests/test_vps_boot.sh
git commit -m "feat: make user creation optional"
```

---

### Task 4: Passwordless sudo registry component

**Files:**
- Modify: `tests/test_vps_boot.sh`
- Modify: `vps-boot.sh:395-435,631-637,859-875,1066-1070`

**Interfaces:**
- Consumes: `USERNAME`, component registry, `component_is_applicable`.
- Produces: `install_sudo_nopasswd`, `check_sudo_nopasswd`, registered key `sudo_nopasswd`, and `VPS_BOOT_SUDOERS_DIR` path override.

- [ ] **Step 1: Write failing component registration and installer tests**

Export before sourcing:

```bash
export VPS_BOOT_SUDOERS_DIR="$TEST_ROOT/sudoers.d"
```

Add:

```bash
test_sudo_nopasswd_is_default_and_root_filtered() {
  [[ ${COMPONENT_DEFAULT[sudo_nopasswd]:-} == 1 ]] || return 1
  USERNAME=alice
  component_is_applicable sudo_nopasswd || return 1
  USERNAME=root
  ! component_is_applicable sudo_nopasswd
}

test_install_sudo_nopasswd_validates_and_installs() {
  local visudo_log="$TEST_ROOT/visudo-log"
  visudo() {
    printf '%s\n' "$*" >> "$visudo_log"
    return 0
  }

  USERNAME=alice
  install_sudo_nopasswd || return 1

  local target="$VPS_BOOT_SUDOERS_DIR/90-vps-boot-alice"
  [[ -f $target ]] || return 1
  [[ $(cat "$target") == 'alice ALL=(ALL:ALL) NOPASSWD: ALL' ]] || return 1
  [[ $(stat -c '%a' "$target") == 440 ]] || return 1
  grep -q -- '-cf' "$visudo_log"
}
```

Register both tests:

```bash
run_test "passwordless sudo defaults on and is root-filtered" test_sudo_nopasswd_is_default_and_root_filtered
run_test "passwordless sudo validates and installs" test_install_sudo_nopasswd_validates_and_installs
```

- [ ] **Step 2: Run tests and verify RED**

Expected: failures because the component and installer do not exist.

- [ ] **Step 3: Implement the atomic sudoers installer**

Add a testable path constant:

```bash
readonly SUDOERS_DIR="${VPS_BOOT_SUDOERS_DIR:-/etc/sudoers.d}"
```

Add the first component block before Docker:

```bash
install_sudo_nopasswd() {
  local target="$SUDOERS_DIR/90-vps-boot-$USERNAME"
  local candidate
  install -d -m 0755 "$SUDOERS_DIR"
  candidate=$(mktemp "$SUDOERS_DIR/.vps-boot-sudo.XXXXXX")
  if ! printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$USERNAME" > "$candidate"; then
    rm -f "$candidate"
    return 1
  fi
  if ! chmod 0440 "$candidate"; then
    rm -f "$candidate"
    return 1
  fi
  if ! visudo -cf "$candidate"; then
    rm -f "$candidate"
    return 1
  fi
  if ! mv -f "$candidate" "$target"; then
    rm -f "$candidate"
    return 1
  fi
}

check_sudo_nopasswd() {
  if sudo -u "$USERNAME" -H sudo -n true >/dev/null 2>&1; then
    ok "passwordless sudo enabled for $USERNAME"
  else
    ko "passwordless sudo unavailable for $USERNAME"
  fi
}

register sudo_nopasswd "Passwordless sudo" "sudo without password prompts" 1 system \
  install_sudo_nopasswd check_sudo_nopasswd
```

Add `sudo` to `bl_update`'s base package list so `visudo` and the `sudo` group are guaranteed on minimal Ubuntu images before this component runs.

Because Task 3 filters this key for root, no special root behavior belongs inside the installer.

- [ ] **Step 4: Add the malformed-candidate regression**

Add this test, which must fail if the implementation moves the candidate before validation:

```bash
test_invalid_sudoers_does_not_replace_active_rule() {
  local target="$VPS_BOOT_SUDOERS_DIR/90-vps-boot-alice"
  mkdir -p "$VPS_BOOT_SUDOERS_DIR"
  printf 'original\n' > "$target"
  visudo() { return 1; }
  USERNAME=alice

  if install_sudo_nopasswd; then
    return 1
  fi

  [[ $(cat "$target") == original ]] || return 1
  ! compgen -G "$VPS_BOOT_SUDOERS_DIR/.vps-boot-sudo.*" >/dev/null
}

run_test "invalid sudoers leaves active rule unchanged" test_invalid_sudoers_does_not_replace_active_rule
```

Also cover an unexpected post-`mktemp` failure under `errexit`:

```bash
test_sudo_nopasswd_cleans_candidate_after_chmod_failure() {
  local target="$VPS_BOOT_SUDOERS_DIR/90-vps-boot-alice"
  mkdir -p "$VPS_BOOT_SUDOERS_DIR"
  printf 'original\n' > "$target"
  chmod() { return 23; }
  USERNAME=alice

  ( set -e; install_sudo_nopasswd )
  local rc=$?

  (( rc != 0 )) || return 1
  [[ $(cat "$target") == original ]] || return 1
  ! compgen -G "$VPS_BOOT_SUDOERS_DIR/.vps-boot-sudo.*" >/dev/null
}

run_test "passwordless sudo cleans candidate after chmod failure" test_sudo_nopasswd_cleans_candidate_after_chmod_failure
```

- [ ] **Step 5: Run Task 4 verification**

Run syntax checks and the full test suite.

Expected: `10 passed, 0 failed`; successful rule mode is 440; invalid candidates do not replace the active rule or leak temporary candidates.

- [ ] **Step 6: Commit Task 4**

```powershell
git add vps-boot.sh tests/test_vps_boot.sh
git commit -m "feat: add passwordless sudo component"
```

---

### Task 5: Owned SSH drop-in and effective lockdown

**Files:**
- Modify: `tests/test_vps_boot.sh`
- Modify: `vps-boot.sh:16-20,654-707,728-775,983-1030`

**Interfaces:**
- Consumes: `USERNAME`, `SSH_PORT`, existing `bl_ssh_harden` and enrollment flow.
- Produces: `write_sshd_dropin <permit-root> <password-auth> <kbd-auth>`, `lockdown_ssh`, `sshd_effective_value <keyword>`, `VPS_BOOT_SSHD_CONFIG`, and `VPS_BOOT_SSHD_DROPIN` path overrides.

- [ ] **Step 1: Write failing drop-in and lockdown tests**

Export before sourcing:

```bash
export VPS_BOOT_SSHD_CONFIG="$TEST_ROOT/sshd_config"
export VPS_BOOT_SSHD_DROPIN="$TEST_ROOT/sshd_config.d/00-vps-boot.conf"
```

Create the main fixture before sourcing:

```bash
mkdir -p "$(dirname "$VPS_BOOT_SSHD_DROPIN")"
printf 'Include %s/*.conf\n' "$(dirname "$VPS_BOOT_SSHD_DROPIN")" > "$VPS_BOOT_SSHD_CONFIG"
```

Add:

```bash
test_sshd_dropin_has_single_managed_values() {
  SSH_PORT=2222
  write_sshd_dropin no yes yes || return 1
  [[ $(grep -c '^Port 2222$' "$VPS_BOOT_SSHD_DROPIN") -eq 1 ]] || return 1
  [[ $(grep -c '^PermitRootLogin no$' "$VPS_BOOT_SSHD_DROPIN") -eq 1 ]] || return 1
  [[ $(grep -c '^PasswordAuthentication yes$' "$VPS_BOOT_SSHD_DROPIN") -eq 1 ]] || return 1
  [[ $(grep -c '^KbdInteractiveAuthentication yes$' "$VPS_BOOT_SSHD_DROPIN") -eq 1 ]]
}

test_lockdown_disables_password_methods_and_reloads() {
  local systemctl_log="$TEST_ROOT/systemctl-log"
  sshd() { return 0; }
  systemctl() { printf '%s\n' "$*" >> "$systemctl_log"; }
  SSH_PORT=2222
  USERNAME=alice

  lockdown_ssh || return 1

  grep -q '^PermitRootLogin no$' "$VPS_BOOT_SSHD_DROPIN" || return 1
  grep -q '^PasswordAuthentication no$' "$VPS_BOOT_SSHD_DROPIN" || return 1
  grep -q '^KbdInteractiveAuthentication no$' "$VPS_BOOT_SSHD_DROPIN" || return 1
  [[ $(cat "$systemctl_log") == 'reload ssh.service' ]]
}

test_invalid_sshd_config_is_not_reloaded() {
  local systemctl_log="$TEST_ROOT/systemctl-invalid-log"
  sshd() { return 1; }
  systemctl() { printf '%s\n' "$*" >> "$systemctl_log"; }
  SSH_PORT=2222
  USERNAME=alice
  ! lockdown_ssh || return 1
  [[ ! -e $systemctl_log ]]
}
```

Register the three tests:

```bash
run_test "SSH drop-in has one value per managed key" test_sshd_dropin_has_single_managed_values
run_test "SSH lockdown disables passwords and reloads" test_lockdown_disables_password_methods_and_reloads
run_test "invalid SSH config is not reloaded" test_invalid_sshd_config_is_not_reloaded
```

Also prove a drop-in write failure cannot fall through under Bash's conditional-command rules:

```bash
test_lockdown_stops_when_dropin_write_fails() {
  local sshd_log="$TEST_ROOT/sshd-after-write-failure-log"
  local systemctl_log="$TEST_ROOT/systemctl-after-write-failure-log"
  write_sshd_dropin() { return 23; }
  sshd() { printf '%s\n' "$*" >> "$sshd_log"; }
  systemctl() { printf '%s\n' "$*" >> "$systemctl_log"; }
  SSH_PORT=2222
  USERNAME=alice

  if lockdown_ssh; then
    return 1
  fi

  [[ ! -e $sshd_log ]] || return 1
  [[ ! -e $systemctl_log ]]
}

run_test "SSH lockdown stops after drop-in write failure" test_lockdown_stops_when_dropin_write_fails
```

- [ ] **Step 2: Run tests and verify RED**

Expected: failures because the SSH helper functions do not exist.

- [ ] **Step 3: Implement the owned drop-in**

Add:

```bash
readonly SSHD_CONFIG="${VPS_BOOT_SSHD_CONFIG:-/etc/ssh/sshd_config}"
readonly SSHD_DROPIN="${VPS_BOOT_SSHD_DROPIN:-/etc/ssh/sshd_config.d/00-vps-boot.conf}"
```

Replace `set_sshd` with:

```bash
write_sshd_dropin() {
  local permit_root=$1 password_auth=$2 kbd_auth=$3
  local candidate
  install -d -m 0755 "$(dirname "$SSHD_DROPIN")"
  candidate=$(mktemp "$(dirname "$SSHD_DROPIN")/.vps-boot-sshd.XXXXXX")
  if ! cat > "$candidate" <<EOF
# Managed by vps-boot
Port $SSH_PORT
PermitRootLogin $permit_root
PasswordAuthentication $password_auth
KbdInteractiveAuthentication $kbd_auth
EOF
  then
    rm -f "$candidate"
    return 1
  fi
  if ! chmod 0644 "$candidate"; then
    rm -f "$candidate"
    return 1
  fi
  if ! mv -f "$candidate" "$SSHD_DROPIN"; then
    rm -f "$candidate"
    return 1
  fi
}
```

Update `bl_ssh_harden` to back up `SSHD_CONFIG`, choose `PermitRootLogin yes` for root and `no` for a created user, call `write_sshd_dropin "$permit_root" yes yes`, then run `sshd -t` before changing services. Remove every call to `set_sshd`.

- [ ] **Step 4: Implement and integrate lockdown**

Add:

```bash
lockdown_ssh() {
  local permit_root=no
  [[ "$USERNAME" == "root" ]] && permit_root=prohibit-password
  write_sshd_dropin "$permit_root" no no || return 1
  sshd -t || return 1
  systemctl reload ssh.service
}
```

In `enroll_ssh_key`, replace the direct `sed` and root `set_sshd` calls with `lockdown_ssh`. Keep key existence, key validity, ownership, and mode checks before this call.

- [ ] **Step 5: Verify effective settings instead of grepping files**

Add:

```bash
sshd_effective_value() {
  local key=${1,,}
  sshd -T -C "user=$USERNAME,host=localhost,addr=127.0.0.1" 2>/dev/null \
    | awk -v wanted="$key" '$1 == wanted { print $2; exit }'
}
```

Update `do_check` to use `sshd_effective_value permitrootlogin`, `passwordauthentication`, and `kbdinteractiveauthentication`. Password lockdown is successful only when both authentication values equal `no`. Keep a warning before enrollment and report a failure when the two values disagree.

- [ ] **Step 6: Add effective-value parsing and root-lockdown tests**

Add these tests:

```bash
test_sshd_effective_value_reads_sshd_T() {
  sshd() {
    printf '%s\n' \
      'port 2222' \
      'permitrootlogin no' \
      'passwordauthentication no' \
      'kbdinteractiveauthentication no'
  }
  USERNAME=alice
  [[ $(sshd_effective_value passwordauthentication) == no ]]
}

test_root_lockdown_is_key_only() {
  sshd() { return 0; }
  systemctl() { return 0; }
  SSH_PORT=2222
  USERNAME=root
  lockdown_ssh || return 1
  grep -q '^PermitRootLogin prohibit-password$' "$VPS_BOOT_SSHD_DROPIN"
}

run_test "effective SSH values come from sshd -T" test_sshd_effective_value_reads_sshd_T
run_test "root lockdown is key-only" test_root_lockdown_is_key_only
```

- [ ] **Step 7: Run Task 5 verification**

Run syntax checks and full tests.

Expected: `16 passed, 0 failed`; one managed line per SSH key; no reload after failed write or validation; both password methods disabled; root becomes key-only.

- [ ] **Step 8: Commit Task 5**

```powershell
git add vps-boot.sh tests/test_vps_boot.sh
git commit -m "fix: enforce effective SSH key-only lockdown"
```

---

### Task 6: Documentation and complete behavior checks

**Files:**
- Modify: `README.md:1-100`
- Modify: `tests/test_vps_boot.sh`

**Interfaces:**
- Consumes: finalized wizard, component names, and SSH behavior.
- Produces: user-facing documentation matching actual defaults and a lightweight README regression check.

- [ ] **Step 1: Write failing README consistency test**

Add:

```bash
test_readme_documents_new_defaults() {
  grep -q 'root-only' "$ROOT_DIR/README.md" || return 1
  grep -q 'Passwordless sudo' "$ROOT_DIR/README.md" || return 1
  grep -q 'three minutes' "$ROOT_DIR/README.md" || return 1
  grep -q 'KbdInteractiveAuthentication' "$ROOT_DIR/README.md"
}
```

Register it with:

```bash
run_test "README documents new defaults" test_readme_documents_new_defaults
```

- [ ] **Step 2: Run tests and verify RED**

Expected: README test fails because these behaviors are not yet documented.

- [ ] **Step 3: Update README**

Revise Why, Baseline, Toolchain, Usage, enrollment, and Recovery sections to state:

- root-only is the default; creating a non-root user is optional;
- QuickStart includes Passwordless sudo only when a user is created;
- Custom shows Passwordless sudo in the existing checkbox list;
- APT waits at most three minutes for background package locks;
- enrollment disables `PasswordAuthentication` and `KbdInteractiveAuthentication` and reloads SSH;
- `check root <port>` is the root-only verification form;
- a created user uses `check <username> <port>`.

Update the wizard transcript so `User account` is first and username/password are conditional.

- [ ] **Step 4: Run Task 6 verification**

Run syntax checks and full tests.

Expected: `17 passed, 0 failed`.

- [ ] **Step 5: Commit Task 6**

```powershell
git add README.md tests/test_vps_boot.sh
git commit -m "docs: explain reliable root and sudo setup"
```

---

### Task 7: Full verification, branch publication, and develop merge

**Files:**
- Verify: `vps-boot.sh`
- Verify: `tests/test_vps_boot.sh`
- Verify: `README.md`

**Interfaces:**
- Consumes: all prior tasks.
- Produces: verified `codex/reliable-bootstrap`, merged and pushed `develop`, untouched `main`.

- [ ] **Step 1: Run fresh full verification**

```powershell
& 'C:\Program Files\Git\bin\bash.exe' -n vps-boot.sh
& 'C:\Program Files\Git\bin\bash.exe' -n tests/test_vps_boot.sh
& 'C:\Program Files\Git\bin\bash.exe' tests/test_vps_boot.sh
git diff --check main...HEAD
```

Expected: both syntax checks exit 0; all 17 tests pass; `git diff --check` emits nothing.

- [ ] **Step 2: Run ShellCheck when installed**

```powershell
if (Get-Command shellcheck -ErrorAction SilentlyContinue) {
  shellcheck vps-boot.sh tests/test_vps_boot.sh
} else {
  Write-Output 'shellcheck unavailable; bash -n and regression suite completed'
}
```

Expected when installed: zero findings and exit 0. If unavailable, record that limitation in the final report without claiming ShellCheck passed.

- [ ] **Step 3: Inspect final scope and history**

```powershell
git status --short
git diff --stat main...HEAD
git log --oneline --decorate main..HEAD
git ls-remote --heads origin main develop 'claude/optional-user-creation-QWBGx'
```

Expected: clean worktree; only planned files plus design/plan docs changed; stale Claude branch absent; remote `main` and rebuilt `develop` still point at the original main commit before merge.

- [ ] **Step 4: Push the feature branch**

```powershell
git push -u origin codex/reliable-bootstrap
```

Expected: remote branch created successfully.

- [ ] **Step 5: Merge into develop without changing main**

```powershell
git switch develop
git pull --ff-only origin develop
git merge --no-ff codex/reliable-bootstrap -m "Merge reliable bootstrap fixes into develop"
```

Expected: merge commit created on `develop`; no conflicts.

- [ ] **Step 6: Re-run verification on the merge result**

Run the full commands from Step 1 while on `develop`.

Expected: all syntax/tests/diff checks pass on the exact merge result.

- [ ] **Step 7: Push develop and verify remote refs**

```powershell
git push origin develop
git ls-remote --heads origin main develop codex/reliable-bootstrap 'claude/optional-user-creation-QWBGx'
```

Expected: `develop` and `codex/reliable-bootstrap` exist at the new commits; stale Claude branch remains absent; `main` remains at `731160a`.
