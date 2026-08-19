#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT_DIR/vps-boot.sh"
PASS_COUNT=0
FAIL_COUNT=0
TEST_FILTER=${TEST_FILTER:-${1:-}}
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
export VPS_BOOT_LOG_FILE="$TEST_ROOT/vps-boot.log"
export VPS_BOOT_APT_LOCK_CONFIG="$TEST_ROOT/99-vps-boot-lock-timeout"
export VPS_BOOT_UNATTENDED_UPGRADES_CONFIG="$TEST_ROOT/20auto-upgrades"
export VPS_BOOT_SUDOERS_DIR="$TEST_ROOT/sudoers.d"
export VPS_BOOT_SSHD_CONFIG="$TEST_ROOT/sshd_config"
export VPS_BOOT_SSHD_DROPIN="$TEST_ROOT/sshd_config.d/00-vps-boot.conf"
export VPS_BOOT_STATE_DIR="$TEST_ROOT/state"
export VPS_BOOT_RUSTUP_HOME="$TEST_ROOT/rustup"
export VPS_BOOT_CARGO_HOME="$TEST_ROOT/cargo"
mkdir -p "$(dirname "$VPS_BOOT_SSHD_DROPIN")"
printf 'Include %s/*.conf\n' "$(dirname "$VPS_BOOT_SSHD_DROPIN")" > "$VPS_BOOT_SSHD_CONFIG"

pass() { printf 'ok - %s\n' "$1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'not ok - %s\n' "$1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
run_test() {
  local label=$1
  shift
  if [[ -n $TEST_FILTER && $label != *"$TEST_FILTER"* ]]; then
    return 0
  fi
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

test_stdin_execution_runs_main() {
  local output
  output=$(bash -s help < "$SCRIPT" 2>&1) || return 1
  grep -q 'COMMANDS' <<< "$output" || return 1
  grep -q 'install' <<< "$output"
}

source "$SCRIPT"

test_registry_entries_are_well_formed() {
  # The register() contract: every key in COMPONENTS names real install/check
  # functions, a known scope, and one of the six fixed groups. The valid groups
  # are spelled out here rather than read from the script, so a typo in
  # COMPONENT_GROUPS cannot make this case pass vacuously.
  local expected_groups="core languages packaging agents cloud infra"

  [[ "${COMPONENT_GROUPS[*]}" == "$expected_groups" ]] || return 1
  (( ${#COMPONENTS[@]} > 0 )) || return 1

  local key
  for key in "${COMPONENTS[@]}"; do
    declare -F "${COMPONENT_INSTALL[$key]:-}" >/dev/null || return 1
    declare -F "${COMPONENT_CHECK[$key]:-}" >/dev/null || return 1
    case "${COMPONENT_SCOPE[$key]:-}" in
      system|user) ;;
      *) return 1 ;;
    esac
    case " $expected_groups " in
      *" ${COMPONENT_GROUP[$key]:-} "*) ;;
      *) return 1 ;;
    esac
  done
}

test_probe_java_lts_jdk_only_probes_lts_majors() {
  # For Java, "newest installable" and "newest LTS" are not the same thing —
  # the probe must only ever call apt --dry-run on LTS majors (17/21/25/29/33/...,
  # i.e. (n - 21) % 4 == 0), never on 22/23/24/26. Simulate noble: only 25 has
  # an installable candidate.
  local probe_log="$TEST_ROOT/java-probe-log"
  apt() {
    [[ $1 == install && $3 == --dry-run ]] || return 0
    printf '%s\n' "$4" >> "$probe_log"
    [[ $4 == openjdk-25-jdk-headless ]]
  }

  local jdk
  jdk=$(probe_java_lts_jdk) || return 1

  [[ $jdk == openjdk-25-jdk-headless ]] || return 1
  grep -qx 'openjdk-25-jdk-headless' "$probe_log" || return 1
  ! grep -qxE 'openjdk-(22|23|24|26)-jdk-headless' "$probe_log"
}

test_probe_java_lts_jdk_fails_when_none_installable() {
  apt() { return 1; }
  ! probe_java_lts_jdk >/dev/null
}

test_check_java_reports_version_via_stderr_redirect() {
  # java -version writes to stderr, not stdout — check_java must redirect
  # 2>&1 or it silently reports "?".
  command() {
    case "$2" in
      java | javac) return 0 ;;
      *) builtin command "$@" ;;
    esac
  }
  java() {
    [[ $1 == -version ]] || return 1
    printf 'openjdk version "25.0.3" 2025-09-16\n' >&2
  }
  PASS=0 FAIL=0
  local out
  out=$(check_java)
  grep -q '✓' <<< "$out" || return 1
  grep -q '25.0.3' <<< "$out"
}

test_check_java_fails_without_javac() {
  # A JRE-only box (java present, javac missing) must fail, not pass on a
  # naive `command -v java`.
  command() {
    case "$2" in
      java) return 0 ;;
      javac) return 1 ;;
      *) builtin command "$@" ;;
    esac
  }
  PASS=0 FAIL=0
  local out
  out=$(check_java)
  grep -q '✗' <<< "$out"
}

test_install_rust_uses_noninteractive_pinned_flags() {
  # Bare `rustup` is interactive and would hang step_run. -y --no-modify-path
  # plus pinned RUSTUP_HOME/CARGO_HOME is the containerised-Rust recipe.
  local src
  src=$(declare -f install_rust)
  grep -q -- '-y --no-modify-path' <<< "$src" || return 1
  # The pinned homes moved into constants shared with check_rust; the defaults
  # they resolve to are asserted where those constants are declared.
  grep -q 'RUSTUP_HOME="\$RUSTUP_HOME_DIR"' <<< "$src" || return 1
  grep -q 'CARGO_HOME="\$CARGO_HOME_DIR"' <<< "$src"
}

test_check_rust_reports_both_rustc_and_cargo_versions() {
  # A half-installed toolchain where cargo is missing (but rustc is present)
  # is the failure worth catching.
  local src
  src=$(declare -f check_rust)
  grep -q 'rustc' <<< "$src" || return 1
  grep -q 'cargo' <<< "$src" || return 1
  # The pinned dir moved into a constant; the default it resolves to has not.
  grep -q 'CARGO_HOME_DIR/bin' <<< "$src" || return 1
  grep -q 'VPS_BOOT_CARGO_HOME:-/usr/local/cargo' "$SCRIPT" || return 1
  grep -q 'VPS_BOOT_RUSTUP_HOME:-/usr/local/rustup' "$SCRIPT"
}

test_install_uv_pins_install_dir() {
  # Upstream defaults to $HOME/.local/bin, not on PATH for a fresh root-only
  # box — mirrors install_herdr's pinned-install-dir fix.
  grep -q 'UV_INSTALL_DIR=/usr/local/bin' <<< "$(declare -f install_uv)"
}

test_check_uv_reports_version() {
  uv() {
    [[ $1 == --version ]] || return 1
    printf 'uv 0.9.7\n'
  }
  PASS=0 FAIL=0
  local out
  out=$(check_uv)
  grep -q '✓' <<< "$out" || return 1
  grep -q '0.9.7' <<< "$out"
}

test_check_uv_fails_when_missing() {
  command() {
    case "$2" in
      uv) return 1 ;;
      *) builtin command "$@" ;;
    esac
  }
  PASS=0 FAIL=0
  local out
  out=$(check_uv)
  grep -q '✗' <<< "$out"
}

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

test_apt_lock_timeout_fragment() {
  install_apt_lock_timeout || return 1
  [[ -f "$VPS_BOOT_APT_LOCK_CONFIG" ]] || return 1
  [[ $(cat "$VPS_BOOT_APT_LOCK_CONFIG") == 'DPkg::Lock::Timeout "180";' ]] || return 1
  remove_apt_lock_timeout || return 1
  [[ ! -e "$VPS_BOOT_APT_LOCK_CONFIG" ]]
}

test_apt_setup_failure_removes_candidate_and_final() {
  mkdir -p "$(dirname "$VPS_BOOT_APT_LOCK_CONFIG")"
  printf 'stale\n' > "$VPS_BOOT_APT_LOCK_CONFIG"
  chmod() { return 23; }

  if install_apt_lock_timeout; then
    return 1
  fi

  [[ ! -e $VPS_BOOT_APT_LOCK_CONFIG ]] || return 1
  ! compgen -G "$(dirname "$VPS_BOOT_APT_LOCK_CONFIG")/.vps-boot-apt.*" >/dev/null
}

test_bl_update_installs_build_essential() {
  grep -q 'build-essential' <<< "$(declare -f bl_update)"
}

test_bl_unattended_installs_package_and_writes_config() {
  local apt_log="$TEST_ROOT/unattended-apt-calls"
  local systemctl_log="$TEST_ROOT/unattended-systemctl-calls"
  apt() { printf '%s\n' "$*" >> "$apt_log"; }
  systemctl() { printf '%s\n' "$*" >> "$systemctl_log"; }

  bl_unattended || return 1

  grep -q '^install -y unattended-upgrades$' "$apt_log" || return 1
  [[ -f $VPS_BOOT_UNATTENDED_UPGRADES_CONFIG ]] || return 1
  [[ $(stat -c '%a' "$VPS_BOOT_UNATTENDED_UPGRADES_CONFIG") == 644 ]] || return 1
  grep -q '^APT::Periodic::Unattended-Upgrade "1";$' "$VPS_BOOT_UNATTENDED_UPGRADES_CONFIG" || return 1
  grep -q 'security' "$VPS_BOOT_UNATTENDED_UPGRADES_CONFIG" || return 1
  grep -q '^Unattended-Upgrade::Automatic-Reboot "false";$' "$VPS_BOOT_UNATTENDED_UPGRADES_CONFIG" || return 1
  grep -q 'apt-daily-upgrade.timer' "$systemctl_log"
}

test_bl_unattended_cleans_candidate_after_chmod_failure() {
  mkdir -p "$(dirname "$VPS_BOOT_UNATTENDED_UPGRADES_CONFIG")"
  printf 'original\n' > "$VPS_BOOT_UNATTENDED_UPGRADES_CONFIG"
  apt() { :; }
  chmod() { return 23; }

  if bl_unattended; then
    return 1
  fi

  [[ $(cat "$VPS_BOOT_UNATTENDED_UPGRADES_CONFIG") == original ]] || return 1
  ! compgen -G "$(dirname "$VPS_BOOT_UNATTENDED_UPGRADES_CONFIG")/.vps-boot-unattended.*" >/dev/null
}

test_bl_unattended_enables_timer_without_starting_it_now() {
  # `enable --now` would restart apt-daily-upgrade.timer mid-install, undoing
  # stop_apt_timers and reopening the exact race from issue #43. bl_unattended
  # must only *enable* it (for future boots) — restore_apt_timers is what
  # starts it again, once the install is done.
  local systemctl_log="$TEST_ROOT/unattended-enable-only-systemctl-calls"
  apt() { :; }
  systemctl() { printf '%s\n' "$*" >> "$systemctl_log"; }

  bl_unattended || return 1

  grep -qx 'enable apt-daily-upgrade.timer' "$systemctl_log" || return 1
  ! grep -q -- '--now' "$systemctl_log"
}

# ── apt/dpkg lock helpers (issue #43) ───────────────────────────────────────
# `wait_for_apt` mitigates the gap DPkg::Lock::Timeout does not cover: that
# option only bounds dpkg's own lock wait *inside* an apt/dpkg invocation, but
# `apt update` takes /var/lib/apt/lists/lock before dpkg is ever invoked, so a
# concurrent apt-daily(-upgrade) run can still fail the install outright.

test_wait_for_apt_returns_immediately_when_unlocked() {
  local fuser_log="$TEST_ROOT/wait-unlocked-fuser-calls"
  local sleep_log="$TEST_ROOT/wait-unlocked-sleep-calls"
  fuser() { printf 'call\n' >> "$fuser_log"; return 1; }
  sleep() { printf '%s\n' "$*" >> "$sleep_log"; }

  wait_for_apt || return 1

  [[ -s $fuser_log ]] || return 1
  [[ ! -e $sleep_log ]]
}

test_wait_for_apt_waits_while_lock_is_held() {
  # Simulates the exact regression: something else holds the lock for a
  # couple of checks, then releases it. The install path must wait for it,
  # not fail on the first attempt.
  local fuser_log="$TEST_ROOT/wait-blocked-fuser-calls"
  local sleep_log="$TEST_ROOT/wait-blocked-sleep-calls"
  local calls=0
  fuser() {
    calls=$((calls + 1))
    printf '%s\n' "$calls" >> "$fuser_log"
    (( calls < 3 ))
  }
  sleep() { printf '%s\n' "$*" >> "$sleep_log"; }

  wait_for_apt || return 1

  [[ $(wc -l < "$fuser_log") -eq 3 ]] || return 1
  [[ $(wc -l < "$sleep_log") -eq 2 ]]
}

test_wait_for_apt_times_out_and_reports() {
  local msg_log="$TEST_ROOT/wait-timeout-msg"
  fuser() { return 0; }
  sleep() { :; }

  if wait_for_apt 2 2>"$msg_log"; then
    return 1
  fi

  grep -qi 'timed out' "$msg_log" || return 1
  grep -q '2' "$msg_log"
}

test_wait_for_apt_defaults_budget_to_apt_lock_timeout_constant() {
  grep -q 'APT_LOCK_TIMEOUT' <<< "$(declare -f wait_for_apt)"
}

test_wait_for_apt_is_a_noop_when_fuser_is_unavailable() {
  # A minimal image without psmisc must not hang the install trying to run a
  # binary that doesn't exist.
  command() {
    case "$2" in
      fuser) return 1 ;;
      *) builtin command "$@" ;;
    esac
  }
  fuser() { return 0; }

  wait_for_apt
}

test_wait_for_apt_precedes_every_apt_update_or_install_call() {
  # Global, source-level check: every real `apt update`/`apt upgrade`/
  # `apt install` invocation in the script must be immediately preceded by a
  # wait_for_apt call. This is what keeps the regression from becoming
  # invisible again the next time a component adds its own apt call.
  local prev="" line trimmed
  while IFS= read -r line; do
    if [[ $line =~ ^[[:space:]]*apt[[:space:]]+(update|upgrade|install) ]]; then
      if [[ $prev != *wait_for_apt* ]]; then
        printf 'missing wait_for_apt before: %s\n' "$line" >&2
        return 1
      fi
    fi
    trimmed=${line#"${line%%[![:space:]]*}"}
    [[ -n $trimmed && $trimmed != \#* ]] && prev=$line
  done < "$SCRIPT"
}

test_stop_apt_timers_stops_timers_and_services() {
  local systemctl_log="$TEST_ROOT/stop-timers-systemctl-calls"
  systemctl() { printf '%s\n' "$*" >> "$systemctl_log"; }

  stop_apt_timers

  grep -q 'apt-daily.timer' "$systemctl_log" || return 1
  grep -q 'apt-daily-upgrade.timer' "$systemctl_log" || return 1
  grep -q 'apt-daily.service' "$systemctl_log" || return 1
  grep -q 'apt-daily-upgrade.service' "$systemctl_log" || return 1
  grep -q '^stop' "$systemctl_log"
}

test_stop_apt_timers_survives_missing_units() {
  systemctl() { return 1; }
  stop_apt_timers
}

test_restore_apt_timers_starts_both_timers() {
  local systemctl_log="$TEST_ROOT/restore-timers-systemctl-calls"
  systemctl() { printf '%s\n' "$*" >> "$systemctl_log"; }

  restore_apt_timers

  grep -q '^start.*apt-daily.timer' "$systemctl_log" || return 1
  grep -q 'apt-daily-upgrade.timer' "$systemctl_log"
}

test_restore_apt_timers_survives_missing_units() {
  systemctl() { return 1; }
  restore_apt_timers
}

test_cmd_install_restores_apt_timers_before_the_verifier() {
  # bl_unattended enables apt-daily-upgrade.timer without --now on purpose, so
  # the timer is inactive for the whole run by design. do_check asserts it is
  # active — run inside the window stop_apt_timers holds open, that assertion
  # reports a false ✗ on every single install (issue #49). Source-level because
  # the behavioural install-flow cases need a root host.
  local src restore_line check_line
  src=$(declare -f cmd_install)
  restore_line=$(grep -n 'restore_apt_timers' <<< "$src" | head -1 | cut -d: -f1)
  # declare -f renders each statement with a trailing semicolon
  check_line=$(grep -n '^ *do_check;\?$' <<< "$src" | head -1 | cut -d: -f1)
  [[ -n $restore_line && -n $check_line ]] || return 1
  (( restore_line < check_line ))
}

test_do_check_delegates_the_unattended_assertion() {
  declare -F do_check_unattended >/dev/null || return 1
  grep -q 'do_check_unattended' <<< "$(declare -f do_check)"
}

test_do_check_unattended_names_which_half_failed() {
  # "not configured or timer inactive" conflated two causes that mean opposite
  # things: a failed install, versus cleanup that was killed before it ran.
  local out
  ok() { printf 'OK %s\n' "$1"; }
  ko() { printf 'KO %s\n' "$1"; }
  systemctl() { return 0; }

  rm -f "$VPS_BOOT_UNATTENDED_UPGRADES_CONFIG"
  out=$(do_check_unattended) || return 1
  grep -q 'KO .*not configured' <<< "$out" || return 1

  printf 'APT::Periodic::Unattended-Upgrade "1";\n' \
    > "$VPS_BOOT_UNATTENDED_UPGRADES_CONFIG"
  out=$(do_check_unattended) || return 1
  grep -q '^OK ' <<< "$out" || return 1

  systemctl() { return 1; }
  out=$(do_check_unattended) || return 1
  grep -q 'KO .*timer' <<< "$out" || return 1
  # a stopped timer must not read as "the install never configured it"
  ! grep -q 'not configured' <<< "$out"
}

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

prepare_stubbed_install_flow() {
  banner() { :; }
  section() { :; }
  body() { :; }
  rail() { :; }
  enroll_ssh_key() { :; }
  do_check() { :; }
  step_run() {
    local label=$1
    shift
    printf '%s\n' "$label" >> "$FLOW_TRACE"
    "$@"
  }
  bl_update() { printf '%s\n' bl_update >> "$FLOW_TRACE"; }
  bl_unattended() { printf '%s\n' bl_unattended >> "$FLOW_TRACE"; }
  bl_user() { printf '%s\n' bl_user >> "$FLOW_TRACE"; }
  bl_ufw() { printf '%s\n' bl_ufw >> "$FLOW_TRACE"; }
  bl_ssh_harden() { printf '%s\n' bl_ssh_harden >> "$FLOW_TRACE"; }
  bl_fail2ban() { printf '%s\n' bl_fail2ban >> "$FLOW_TRACE"; }
  stub_component_install() { :; }

  local key
  for key in "${COMPONENTS[@]}"; do
    COMPONENT_INSTALL[$key]=stub_component_install
  done

  rm -rf "$VPS_BOOT_STATE_DIR"
  rm -f "$VPS_BOOT_APT_LOCK_CONFIG"
}

test_cmd_install_root_full_install_flow() {
  local expected="" key
  local text_log="$TEST_ROOT/root-text-prompts"
  local password_log="$TEST_ROOT/root-password-prompts"
  FLOW_TRACE="$TEST_ROOT/root-flow-trace"
  prepare_stubbed_install_flow || return 1
  prompt_radio() {
    local label=$1 outvar=$2 value
    case "$label" in
      "User account") value=skip ;;
      "Install mode") value="Full install" ;;
      "Continue?") value=Continue ;;
      *) return 90 ;;
    esac
    printf -v "$outvar" '%s' "$value"
  }
  prompt_text() {
    local label=$1 outvar=$2
    printf '%s\n' "$label" >> "$text_log"
    [[ $label == "SSH port" ]] || return 91
    printf -v "$outvar" '%s' 2222
  }
  prompt_password() { printf '%s\n' "$1" >> "$password_log"; return 92; }
  prompt_multiselect() { return 93; }

  cmd_install "" 2222 >/dev/null || return 1

  [[ $(cat "$text_log") == "SSH port" ]] || return 1
  [[ ! -e $password_log ]] || return 1
  ! grep -q '^bl_user$' "$FLOW_TRACE" || return 1
  [[ -f $VPS_BOOT_STATE_DIR/components ]] || return 1
  for key in "${COMPONENTS[@]}"; do
    component_is_applicable "$key" || continue
    [[ ${COMPONENT_DEFAULT[$key]} == 1 ]] && expected+="$key"$'\n'
  done
  [[ $(cat "$VPS_BOOT_STATE_DIR/components") == "${expected%$'\n'}" ]] || return 1
  ! grep -qx sudo_nopasswd "$VPS_BOOT_STATE_DIR/components"
}

test_cmd_install_created_user_custom_flow() {
  local text_log="$TEST_ROOT/create-text-prompts"
  local password_log="$TEST_ROOT/create-password-prompts"
  local multiselect_log="$TEST_ROOT/create-multiselect"
  FLOW_TRACE="$TEST_ROOT/create-flow-trace"
  prepare_stubbed_install_flow || return 1
  id() { return 1; }
  prompt_radio() {
    local label=$1 outvar=$2 value
    case "$label" in
      "User account") value=create ;;
      "Install mode") value=Custom ;;
      "Continue?") value=Continue ;;
      *) return 90 ;;
    esac
    printf -v "$outvar" '%s' "$value"
  }
  prompt_text() {
    local label=$1 outvar=$2
    printf '%s\n' "$label" >> "$text_log"
    case "$label" in
      Username) printf -v "$outvar" '%s' alice ;;
      "SSH port") printf -v "$outvar" '%s' 2222 ;;
      *) return 91 ;;
    esac
  }
  prompt_password() {
    printf '%s\n' "$1" >> "$password_log"
    printf -v "$2" '%s' secret
  }
  prompt_multiselect() {
    local label=$1
    shift
    printf '%s\n' "$@" > "$multiselect_log"
    PROMPT_MSEL_RESULT=(sudo_nopasswd)
  }

  cmd_install "" 2222 >/dev/null || return 1

  [[ $(cat "$text_log") == $'Username\nSSH port' ]] || return 1
  [[ $(cat "$password_log") == 'Password for alice' ]] || return 1
  grep -q '^bl_user$' "$FLOW_TRACE" || return 1
  grep -q '^sudo_nopasswd|' "$multiselect_log" || return 1
  # the option string carries the group as a fifth field, not a second channel
  grep -qx 'docker|Docker + Compose|containers + compose plugin|1|core' "$multiselect_log" || return 1
  grep -qx 'caddy|.*|1|infra' "$multiselect_log" || return 1
  [[ $(cat "$VPS_BOOT_STATE_DIR/components") == sudo_nopasswd ]]
}

test_cmd_install_runs_bl_unattended_between_update_and_user() {
  FLOW_TRACE="$TEST_ROOT/order-flow-trace"
  prepare_stubbed_install_flow || return 1
  prompt_radio() {
    local label=$1 outvar=$2 value
    case "$label" in
      "User account") value=create ;;
      "Install mode") value="Full install" ;;
      "Continue?") value=Continue ;;
      *) return 90 ;;
    esac
    printf -v "$outvar" '%s' "$value"
  }
  prompt_text() {
    local label=$1 outvar=$2
    case "$label" in
      Username) printf -v "$outvar" '%s' alice ;;
      "SSH port") printf -v "$outvar" '%s' 2222 ;;
      *) return 91 ;;
    esac
  }
  prompt_password() { printf -v "$2" '%s' secret; }
  prompt_multiselect() { PROMPT_MSEL_RESULT=(); }

  cmd_install "" 2222 >/dev/null || return 1

  local update_line unattended_line user_line
  update_line=$(grep -n '^bl_update$' "$FLOW_TRACE" | cut -d: -f1)
  unattended_line=$(grep -n '^bl_unattended$' "$FLOW_TRACE" | cut -d: -f1)
  user_line=$(grep -n '^bl_user$' "$FLOW_TRACE" | cut -d: -f1)
  [[ -n $update_line && -n $unattended_line && -n $user_line ]] || return 1
  (( update_line < unattended_line )) || return 1
  (( unattended_line < user_line ))
}

test_cmd_install_empty_selection_runs_baseline_only() {
  # Custom + `n` is the replacement for a third "baseline only" mode, so an
  # empty selection must still reach Confirm and run the install.
  FLOW_TRACE="$TEST_ROOT/empty-selection-trace"
  prepare_stubbed_install_flow || return 1
  local body_log="$TEST_ROOT/empty-selection-body"
  body() { printf '%s\n' "$1" >> "$body_log"; }
  prompt_radio() {
    local label=$1 outvar=$2 value
    case "$label" in
      "User account") value=skip ;;
      "Install mode") value=Custom ;;
      "Continue?") value=Continue ;;
      *) return 90 ;;
    esac
    printf -v "$outvar" '%s' "$value"
  }
  prompt_text() { printf -v "$2" '%s' 2222; }
  prompt_password() { return 92; }
  prompt_multiselect() { PROMPT_MSEL_RESULT=(); }

  cmd_install "" 2222 >/dev/null || return 1

  grep -q '^bl_fail2ban$' "$FLOW_TRACE" || return 1
  [[ -f $VPS_BOOT_STATE_DIR/components ]] || return 1
  [[ ! -s $VPS_BOOT_STATE_DIR/components ]] || return 1
  grep -q 'baseline only' "$body_log"
}

test_cmd_install_failure_cleans_apt_fragment() {
  FLOW_TRACE="$TEST_ROOT/failing-flow-trace"
  prepare_stubbed_install_flow || return 1
  prompt_radio() {
    local label=$1 outvar=$2 value
    case "$label" in
      "User account") value=skip ;;
      "Install mode") value="Full install" ;;
      "Continue?") value=Continue ;;
      *) return 90 ;;
    esac
    printf -v "$outvar" '%s' "$value"
  }
  prompt_text() { printf -v "$2" '%s' 2222; }
  prompt_password() { return 92; }
  prompt_multiselect() { return 93; }
  bl_update() { return 37; }

  ( set -e; cmd_install "" 2222 >/dev/null 2>&1 )
  local rc=$?

  (( rc == 37 )) || return 1
  [[ ! -e $VPS_BOOT_APT_LOCK_CONFIG ]]
}

test_cmd_install_arms_cleanup_before_apt_setup() {
  FLOW_TRACE="$TEST_ROOT/setup-failing-flow-trace"
  prepare_stubbed_install_flow || return 1
  prompt_radio() {
    local label=$1 outvar=$2 value
    case "$label" in
      "User account") value=skip ;;
      "Install mode") value="Full install" ;;
      "Continue?") value=Continue ;;
      *) return 90 ;;
    esac
    printf -v "$outvar" '%s' "$value"
  }
  prompt_text() { printf -v "$2" '%s' 2222; }
  prompt_password() { return 92; }
  prompt_multiselect() { return 93; }
  install_apt_lock_timeout() {
    printf 'partial\n' > "$VPS_BOOT_APT_LOCK_CONFIG"
    return 41
  }

  ( set -e; cmd_install "" 2222 >/dev/null 2>&1 )
  local rc=$?

  (( rc == 41 )) || return 1
  [[ ! -e $VPS_BOOT_APT_LOCK_CONFIG ]]
}

test_cmd_install_stops_apt_timers_before_first_apt_call() {
  # stop_apt_timers must run before bl_update — the earliest real apt call —
  # or the fix does nothing for the very first race window.
  FLOW_TRACE="$TEST_ROOT/stop-timers-order-trace"
  prepare_stubbed_install_flow || return 1
  # This host has no root; neutralise the `$EUID -eq 0` guard the same way
  # every other stub in prepare_stubbed_install_flow neutralises real system
  # calls, so the test exercises the actual trap/ordering logic instead of
  # only ever failing at "Must run as root."
  die() { :; }
  prompt_radio() {
    local label=$1 outvar=$2 value
    case "$label" in
      "User account") value=skip ;;
      "Install mode") value="Full install" ;;
      "Continue?") value=Continue ;;
      *) return 90 ;;
    esac
    printf -v "$outvar" '%s' "$value"
  }
  prompt_text() { printf -v "$2" '%s' 2222; }
  prompt_password() { return 92; }
  prompt_multiselect() { return 93; }
  stop_apt_timers() { printf 'stop_apt_timers\n' >> "$FLOW_TRACE"; }
  restore_apt_timers() { printf 'restore_apt_timers\n' >> "$FLOW_TRACE"; }

  cmd_install "" 2222 >/dev/null || return 1

  local stop_line update_line
  stop_line=$(grep -n '^stop_apt_timers$' "$FLOW_TRACE" | cut -d: -f1)
  update_line=$(grep -n '^bl_update$' "$FLOW_TRACE" | cut -d: -f1)
  [[ -n $stop_line && -n $update_line ]] || return 1
  (( stop_line < update_line ))
}

test_cmd_install_restores_apt_timers_on_success() {
  FLOW_TRACE="$TEST_ROOT/restore-timers-success-trace"
  prepare_stubbed_install_flow || return 1
  die() { :; }
  prompt_radio() {
    local label=$1 outvar=$2 value
    case "$label" in
      "User account") value=skip ;;
      "Install mode") value="Full install" ;;
      "Continue?") value=Continue ;;
      *) return 90 ;;
    esac
    printf -v "$outvar" '%s' "$value"
  }
  prompt_text() { printf -v "$2" '%s' 2222; }
  prompt_password() { return 92; }
  prompt_multiselect() { return 93; }
  stop_apt_timers() { :; }
  restore_apt_timers() { printf 'restore_apt_timers\n' >> "$FLOW_TRACE"; }

  cmd_install "" 2222 >/dev/null || return 1

  grep -qx 'restore_apt_timers' "$FLOW_TRACE"
}

test_cmd_install_restores_apt_timers_when_a_step_fails() {
  # The acceptance criterion that matters most: a mid-run failure must not
  # leave automatic security updates disabled on the host.
  FLOW_TRACE="$TEST_ROOT/restore-timers-failure-trace"
  prepare_stubbed_install_flow || return 1
  die() { :; }
  prompt_radio() {
    local label=$1 outvar=$2 value
    case "$label" in
      "User account") value=skip ;;
      "Install mode") value="Full install" ;;
      "Continue?") value=Continue ;;
      *) return 90 ;;
    esac
    printf -v "$outvar" '%s' "$value"
  }
  prompt_text() { printf -v "$2" '%s' 2222; }
  prompt_password() { return 92; }
  prompt_multiselect() { return 93; }
  stop_apt_timers() { :; }
  restore_apt_timers() { printf 'restore_apt_timers\n' >> "$FLOW_TRACE"; }
  bl_update() { return 37; }

  ( set -e; cmd_install "" 2222 >/dev/null 2>&1 )
  local rc=$?

  (( rc == 37 )) || return 1
  grep -qx 'restore_apt_timers' "$FLOW_TRACE"
}

test_cmd_install_arms_timer_restore_before_stopping_timers() {
  # Mirrors test_cmd_install_arms_cleanup_before_apt_setup: if stop_apt_timers
  # itself fails partway, the EXIT trap must already be armed to restore them.
  FLOW_TRACE="$TEST_ROOT/arm-timer-restore-trace"
  prepare_stubbed_install_flow || return 1
  die() { :; }
  prompt_radio() {
    local label=$1 outvar=$2 value
    case "$label" in
      "User account") value=skip ;;
      "Install mode") value="Full install" ;;
      "Continue?") value=Continue ;;
      *) return 90 ;;
    esac
    printf -v "$outvar" '%s' "$value"
  }
  prompt_text() { printf -v "$2" '%s' 2222; }
  prompt_password() { return 92; }
  prompt_multiselect() { return 93; }
  restore_apt_timers() { printf 'restore_apt_timers\n' >> "$FLOW_TRACE"; }
  stop_apt_timers() { return 41; }

  ( set -e; cmd_install "" 2222 >/dev/null 2>&1 )
  local rc=$?

  (( rc == 41 )) || return 1
  grep -qx 'restore_apt_timers' "$FLOW_TRACE"
}

# ── signal handling (real-world regression: SSH drops mid-prompt) ──────────
# The EXIT trap alone does not cover a shell killed by an untrapped fatal
# signal: bash's default disposition for SIGHUP/SIGTERM is to terminate the
# process immediately, bypassing the EXIT trap entirely. That is exactly what
# happened on the first real run of #43's fix — the SSH connection dropped
# while `enroll_ssh_key`'s prompt was waiting on `/dev/tty`, the shell died on
# SIGHUP, and cmd_install_cleanup never ran. These two run cmd_install as a
# real background process (not a plain function call) so a real signal can be
# delivered mid-run, and assert cleanup still happened before it died.
assert_cmd_install_signal_restores_timers() {
  local signal=$1 expected_rc=$2

  cmd_install "" 2222 >/dev/null 2>&1 &
  local pid=$!
  # Safety net: if signal delivery does not work in this shell, don't hang
  # the suite — force it down after the stub's own 5s sleep would anyway.
  ( sleep 6; kill -9 "$pid" 2>/dev/null ) &
  local watchdog=$!

  local i
  for ((i = 0; i < 50; i++)); do
    grep -qx waiting "$FLOW_TRACE" 2>/dev/null && break
    sleep 0.1
  done
  if ! grep -qx waiting "$FLOW_TRACE" 2>/dev/null; then
    kill -9 "$pid" "$watchdog" 2>/dev/null
    return 1
  fi

  kill -s "$signal" "$pid"
  wait "$pid"
  local rc=$?
  kill "$watchdog" 2>/dev/null

  (( rc == expected_rc )) || return 1
  # Exactly once: EXIT and the signal trap must not both fire cleanup for the
  # same termination, or a real `remove_apt_lock_timeout`/systemctl call
  # would run twice for one event.
  [[ $(grep -cx 'restore_apt_timers' "$FLOW_TRACE") -eq 1 ]]
}

# NOTE ON PORTABILITY OF THE TWO TESTS BELOW: on real Ubuntu/Linux bash, an
# untrapped fatal signal (no `trap ... HUP`) bypasses the EXIT trap entirely —
# that gap is the actual bug (see issue #43 follow-up). This repo's dev/test
# host is Git Bash on Windows (MSYS2), whose signal emulation runs the EXIT
# trap even for an *untrapped* SIGHUP/SIGTERM, which real Linux bash does not
# do. That means these two behavioural tests cannot go red on this host even
# without the fix below — they still correctly verify the post-fix behaviour
# (single, idempotent cleanup with the right exit code) and will genuinely
# red/green on Linux CI. test_cmd_install_traps_hup_int_term_for_cleanup
# below is the one that reliably reds on every host, since it asserts the
# trap registrations exist in source rather than relying on how a given
# platform delivers the signal.

test_cmd_install_restores_apt_timers_on_sighup() {
  # The concrete regression: a dropped SSH connection delivers SIGHUP.
  FLOW_TRACE="$TEST_ROOT/sighup-flow-trace"
  prepare_stubbed_install_flow || return 1
  die() { :; }
  prompt_radio() {
    local label=$1 outvar=$2 value
    case "$label" in
      "User account") value=skip ;;
      "Install mode") value="Full install" ;;
      "Continue?") value=Continue ;;
      *) return 90 ;;
    esac
    printf -v "$outvar" '%s' "$value"
  }
  prompt_text() { printf -v "$2" '%s' 2222; }
  prompt_password() { return 92; }
  prompt_multiselect() { return 93; }
  stop_apt_timers() { :; }
  restore_apt_timers() { printf 'restore_apt_timers\n' >> "$FLOW_TRACE"; }
  # Blocks at the exact point that bit: the enroll_ssh_key prompt, after
  # every step has already run.
  enroll_ssh_key() { printf 'waiting\n' >> "$FLOW_TRACE"; sleep 5; }

  assert_cmd_install_signal_restores_timers HUP 129
}

test_cmd_install_restores_apt_timers_on_sigterm() {
  FLOW_TRACE="$TEST_ROOT/sigterm-flow-trace"
  prepare_stubbed_install_flow || return 1
  die() { :; }
  prompt_radio() {
    local label=$1 outvar=$2 value
    case "$label" in
      "User account") value=skip ;;
      "Install mode") value="Full install" ;;
      "Continue?") value=Continue ;;
      *) return 90 ;;
    esac
    printf -v "$outvar" '%s' "$value"
  }
  prompt_text() { printf -v "$2" '%s' 2222; }
  prompt_password() { return 92; }
  prompt_multiselect() { return 93; }
  stop_apt_timers() { :; }
  restore_apt_timers() { printf 'restore_apt_timers\n' >> "$FLOW_TRACE"; }
  enroll_ssh_key() { printf 'waiting\n' >> "$FLOW_TRACE"; sleep 5; }

  assert_cmd_install_signal_restores_timers TERM 143
}

test_cmd_install_traps_hup_int_term_for_cleanup() {
  # Source-level, platform-independent complement to the two behavioural
  # tests above: asserts the actual trap registrations exist, so this one
  # reds/greens reliably regardless of how a given host's bash delivers
  # signals to background jobs.
  local src
  src=$(declare -f cmd_install)
  grep -qE "trap[^|&]*HUP" <<< "$src" || return 1
  grep -qE "trap[^|&]*INT" <<< "$src" || return 1
  grep -qE "trap[^|&]*TERM" <<< "$src" || return 1
  grep -q 'cmd_install_handle_signal' <<< "$src"
}

test_cmd_install_signal_handler_disarms_traps_before_cleanup() {
  # The idempotency guarantee: the handler must disarm every trap (so the
  # `exit` it calls doesn't re-fire the EXIT trap and double-run cleanup)
  # before running cleanup, not after.
  local src
  src=$(declare -f cmd_install_handle_signal)
  local disarm_line cleanup_line
  disarm_line=$(grep -n "trap -" <<< "$src" | head -1 | cut -d: -f1)
  cleanup_line=$(grep -n 'cmd_install_cleanup' <<< "$src" | head -1 | cut -d: -f1)
  [[ -n $disarm_line && -n $cleanup_line ]] || return 1
  (( disarm_line < cleanup_line ))
}

# ── wizard rendering helpers ────────────────────────────────────────────────
# The grid glyphs are multi-byte; ${#s} counts bytes under the C locale, so
# every width assertion goes through this ASCII proxy instead.
ui_plain() {
  local s=$1
  s=$(printf '%s' "$s" | sed -e 's/\x1b\[[0-9;]*m//g')
  s=${s//│/|}
  s=${s//◇/o}
  s=${s//◆/O}
  s=${s//◉/@}
  s=${s//◌/_}
  s=${s//›/>}
  s=${s//·/-}
  s=${s//—/-}
  s=${s//●/*}
  s=${s//○/o}
  s=${s//↑/^}
  s=${s//↓/v}
  s=${s//←/<}
  s=${s//→/>}
  printf '%s' "$s"
}

ui_width_of() {
  local plain
  plain=$(ui_plain "$1")
  printf '%s' "${#plain}"
}

msel_fixture() {
  # Bake the value into the stub rather than reading a local: term_cols is
  # resolved dynamically, so a same-named local inside the script would shadow
  # this one.
  eval "term_cols() { printf '%s' ${1:-80}; }"
  local -a opts=()
  local key
  for key in "${COMPONENTS[@]}"; do
    component_is_applicable "$key" || continue
    opts+=("${key}|${COMPONENT_NAME[$key]}|${COMPONENT_DESC[$key]}|${COMPONENT_DEFAULT[$key]}|${COMPONENT_GROUP[$key]}")
  done
  msel_parse "Components" "${opts[@]}" || return 1
  msel_layout || return 1
  msel_build
}

test_vis_len_counts_glyphs_as_one_column() {
  # ${#s} counts bytes under the C locale; every rendering width decision
  # depends on this helper disagreeing with it for multi-byte glyphs.
  [[ $(vis_len "abc") == 3 ]] || return 1
  [[ $(vis_len "│  ◉ Go") == 7 ]] || return 1
  [[ $(vis_len "a · b") == 5 ]] || return 1
  [[ $(vis_len "↑↓←→") == 4 ]]
}

test_install_mode_counts_line_fits_80_columns() {
  # prompt_radio drops a continuation line it cannot fit, so a counts string
  # that outgrew 80 columns would silently vanish from the install-mode label.
  # "│  " + at least 2 indent + 3 gap leaves 72.
  local counts
  USERNAME=alice
  counts=$(component_group_counts $(full_install_keys))
  [[ -n $counts ]] || return 1
  (( $(vis_len "$counts") <= 72 ))
}

test_component_group_counts_follow_group_order() {
  # Counts render in COMPONENT_GROUPS order regardless of argument order, and
  # empty groups are omitted entirely.
  [[ $(component_group_counts docker node bun) == "core 1 · languages 1 · packaging 1" ]] || return 1
  [[ $(component_group_counts bun node docker) == "core 1 · languages 1 · packaging 1" ]] || return 1
  [[ $(component_group_counts caddy herdr) == "infra 2" ]]
}

test_full_install_keys_are_registry_computed() {
  # The Full install label's count must come from the registry and respect
  # component_is_applicable — root-only mode drops exactly sudo_nopasswd.
  local root_keys created_keys
  USERNAME=root
  root_keys=$(full_install_keys)
  USERNAME=alice
  created_keys=$(full_install_keys)

  local -a root_a=($root_keys) created_a=($created_keys)
  (( ${#created_a[@]} - ${#root_a[@]} == 1 )) || return 1
  grep -qw sudo_nopasswd <<< "$created_keys" || return 1
  ! grep -qw sudo_nopasswd <<< "$root_keys" || return 1

  # Independently recompute the per-group counts from the registry.
  local g expected="" c key
  for g in "${COMPONENT_GROUPS[@]}"; do
    c=0
    for key in "${created_a[@]}"; do
      [[ ${COMPONENT_GROUP[$key]} == "$g" ]] && c=$((c + 1))
    done
    (( c == 0 )) && continue
    [[ -n $expected ]] && expected+=" · "
    expected+="$g $c"
  done
  [[ $(component_group_counts "${created_a[@]}") == "$expected" ]]
}

test_install_mode_label_names_no_tools() {
  # A hardcoded enumeration is exactly what rotted before. The Install mode
  # block must not spell any component name out.
  local block key
  block=$(grep -n 'Install mode' -A 4 "$SCRIPT")
  [[ -n $block ]] || return 1
  for key in "${COMPONENTS[@]}"; do
    (( ${#COMPONENT_NAME[$key]} >= 4 )) || continue
    if grep -Fq "${COMPONENT_NAME[$key]}" <<< "$block"; then
      return 1
    fi
  done
  grep -q 'full_install_option' <<< "$block"
}

test_selection_summary_full_collapses_to_group_counts() {
  [[ $(selection_summary 80 "docker gh node" "docker gh node") == "all 3  ·  core 2 · languages 1" ]]
}

test_selection_summary_partial_lists_skipped_names() {
  [[ $(selection_summary 80 "docker gh node bun pnpm" "docker gh node") \
     == "3 of 5  ·  skipped: Bun · pnpm" ]]
}

test_selection_summary_lists_selected_when_it_is_shorter() {
  [[ $(selection_summary 80 "docker gh node bun pnpm" "docker") \
     == "1 of 5  ·  selected: Docker + Compose" ]]
}

test_selection_summary_full_never_exceeds_its_budget() {
  # The partial path has always truncated; the full path did not, and at the
  # real registry size it overflows. The Confirm screen's budget is
  # `term_cols - 13`, so on an 80-column terminal it is 67 — while
  # "all 23  ·  core 4 · languages 5 · packaging 3 · agents 6 · cloud 3 ·
  # infra 2" is 76 visible characters. It wrapped, and the wrapped remainder
  # carries no rail prefix.
  local -a all=("${COMPONENTS[@]}")
  local out
  out=$(selection_summary 67 "${all[*]}" "${all[*]}")
  (( $(ui_width_of "$out") <= 67 )) || return 1
  # still says how many, still names the groups it had room for
  grep -q "^all ${#all[@]}" <<< "$out"
}

test_selection_summary_full_keeps_every_group_when_it_fits() {
  # Degrading is a last resort — with room, no group is dropped and no
  # "+N more" appears.
  local -a all=("${COMPONENTS[@]}")
  local out
  out=$(selection_summary 120 "${all[*]}" "${all[*]}")
  [[ "$out" == "all ${#all[@]}  ·  $(component_group_counts "${all[@]}")" ]]
}

test_selection_summary_full_degrades_to_the_count_alone() {
  # Narrower than even one group count: the bare count is what survives.
  local -a all=("${COMPONENTS[@]}")
  [[ $(selection_summary 12 "${all[*]}" "${all[*]}") == "all ${#all[@]}" ]]
}

test_selection_summary_never_exceeds_its_budget() {
  # The original defect: an unbounded ` · `-joined list wraps and the wrapped
  # remainder carries no rail prefix.
  local -a all=("${COMPONENTS[@]}")
  local -a chosen=("${all[@]:0:12}")
  local out
  out=$(selection_summary 60 "${all[*]}" "${chosen[*]}")
  (( $(ui_width_of "$out") <= 60 )) || return 1
  grep -q 'more' <<< "$out"
}

test_msel_columns_degrade_on_narrow_terminals() {
  [[ $(msel_columns 80) == 3 ]] || return 1
  [[ $(msel_columns 60) == 2 ]] || return 1
  [[ $(msel_columns 40) == 1 ]] || return 1
  [[ $(msel_columns 20) == 1 ]]
}

test_msel_grid_fits_an_80x24_terminal() {
  msel_fixture 80 || return 1
  local line
  for line in "${MSEL_LINES[@]}"; do
    (( $(ui_width_of "$line") <= 80 )) || return 1
  done
  # 24 rows minus the shell prompt and the blank separator above the block.
  (( ${#MSEL_LINES[@]} <= 22 )) || return 1
  (( ${#MSEL_LINES[@]} >= 4 ))
}

test_msel_grid_degrades_to_fewer_columns_at_60() {
  local wide narrow
  msel_fixture 80 || return 1
  wide=${#MSEL_LINES[@]}
  msel_fixture 60 || return 1
  narrow=${#MSEL_LINES[@]}
  (( narrow > wide )) || return 1
  local line
  for line in "${MSEL_LINES[@]}"; do
    (( $(ui_width_of "$line") <= 60 )) || return 1
  done
}

test_msel_grid_groups_rows_in_registry_group_order() {
  msel_fixture 80 || return 1
  local line plain seen="" g
  for line in "${MSEL_LINES[@]}"; do
    plain=$(ui_plain "$line")
    for g in "${COMPONENT_GROUPS[@]}"; do
      if [[ $plain == "|  $g "* ]]; then
        seen+="${seen:+ }$g"
      fi
    done
  done
  [[ $seen == "${COMPONENT_GROUPS[*]}" ]] || return 1
  # The first core row carries the first three core components, in order.
  local first_core=""
  for line in "${MSEL_LINES[@]}"; do
    plain=$(ui_plain "$line")
    if [[ $plain == "|  core "* ]]; then first_core=$plain; break; fi
  done
  [[ $first_core == *"Passwordless sudo"*"CLI tools"*"Docker + Compose"* ]]
}

test_msel_header_counts_track_select_all_and_none() {
  msel_fixture 80 || return 1
  local n=${#MSEL_KEYS[@]}
  msel_select_all
  msel_build
  [[ $(ui_plain "${MSEL_LINES[0]}") == *"$n selected - 0 skipped"* ]] || return 1
  msel_select_none
  msel_build
  [[ $(ui_plain "${MSEL_LINES[0]}") == *"0 selected - $n skipped"* ]] || return 1
  # and the glyphs follow — ui_plain maps ◉ to "@", which no component name uses
  local line ticked=0
  for line in "${MSEL_LINES[@]}"; do
    case $(ui_plain "$line") in *@*) ticked=1 ;; esac
  done
  (( ticked == 0 )) || return 1
  msel_select_all
  msel_build
  ticked=0
  for line in "${MSEL_LINES[@]}"; do
    case $(ui_plain "$line") in *@*) ticked=1 ;; esac
  done
  (( ticked == 1 ))
}

test_msel_navigation_is_two_dimensional() {
  msel_fixture 80 || return 1
  local n=${#MSEL_KEYS[@]}
  MSEL_CURRENT=0
  msel_right
  (( MSEL_CURRENT == 1 )) || return 1
  # core has 4 entries over 3 columns: row 1 holds only index 3, so a down
  # from column 1 clamps to it rather than falling out of the group.
  msel_down
  (( MSEL_CURRENT == 3 )) || return 1
  msel_up
  (( MSEL_CURRENT == 0 )) || return 1
  msel_left
  (( MSEL_CURRENT == n - 1 )) || return 1
  msel_right
  (( MSEL_CURRENT == 0 ))
}

test_msel_redraw_count_matches_what_was_printed() {
  # The bug this replaces: a blind `\033[<n>A` of exactly one row per option,
  # which lands in the wrong place as soon as the block has scrolled.
  local printed_file="$TEST_ROOT/msel-printed"
  msel_fixture 80 || return 1
  msel_print_all > "$printed_file"
  local printed
  printed=$(wc -l < "$printed_file")
  (( printed == ${#MSEL_LINES[@]} )) || return 1

  term_lines() { printf '10'; }
  [[ $(msel_visible_rows) == 9 ]] || return 1
  term_lines() { printf '100'; }
  [[ $(msel_visible_rows) == "${#MSEL_LINES[@]}" ]]
}

test_msel_collect_writes_selected_keys() {
  msel_fixture 80 || return 1
  msel_select_none
  MSEL_CURRENT=0
  msel_toggle
  msel_right
  msel_toggle
  msel_collect
  [[ ${#PROMPT_MSEL_RESULT[@]} -eq 2 ]] || return 1
  [[ ${PROMPT_MSEL_RESULT[0]} == "${MSEL_KEYS[0]}" ]] || return 1
  [[ ${PROMPT_MSEL_RESULT[1]} == "${MSEL_KEYS[1]}" ]]
}

test_no_old_mode_name_references_remain() {
  # Built from fragments so this assertion does not match its own source.
  local pat="Quick""Start"
  ! grep -rn "$pat" \
    "$SCRIPT" "$ROOT_DIR/tests" "$ROOT_DIR/README.md" "$ROOT_DIR/docs/planning/SPECS.md"
}

test_root_skips_docker_group_change() {
  local calls="$TEST_ROOT/usermod-calls"
  usermod() { printf '%s\n' "$*" >> "$calls"; }
  USERNAME=root
  add_docker_group_if_needed || return 1
  [[ ! -e $calls ]]
}

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

test_sshd_dropin_has_single_managed_values() {
  SSH_PORT=2222
  write_sshd_dropin no yes yes || return 1
  [[ $(grep -c '^Port 2222$' "$VPS_BOOT_SSHD_DROPIN") -eq 1 ]] || return 1
  [[ $(grep -c '^PermitRootLogin no$' "$VPS_BOOT_SSHD_DROPIN") -eq 1 ]] || return 1
  [[ $(grep -c '^PasswordAuthentication yes$' "$VPS_BOOT_SSHD_DROPIN") -eq 1 ]] || return 1
  [[ $(grep -c '^KbdInteractiveAuthentication yes$' "$VPS_BOOT_SSHD_DROPIN") -eq 1 ]]
}

reset_real_sshd_fixture() {
  rm -rf "$(dirname "$VPS_BOOT_SSHD_DROPIN")"
  mkdir -p "$(dirname "$VPS_BOOT_SSHD_DROPIN")"
  cat > "$VPS_BOOT_SSHD_CONFIG" <<EOF
Include $(dirname "$VPS_BOOT_SSHD_DROPIN")/*.conf
HostKey /etc/ssh/ssh_host_ed25519_key
PidFile $TEST_ROOT/sshd.pid
UsePAM no
EOF
}

write_previous_sshd_dropin() {
  cat > "$VPS_BOOT_SSHD_DROPIN" <<'EOF'
# previous policy
Port 2200
PermitRootLogin yes
PasswordAuthentication yes
KbdInteractiveAuthentication yes
EOF
  chmod 0644 "$VPS_BOOT_SSHD_DROPIN"
}

test_sshd_syntax_failure_restores_previous_dropin() {
  local before systemctl_log="$TEST_ROOT/systemctl-syntax-failure"
  reset_real_sshd_fixture || return 1
  write_previous_sshd_dropin || return 1
  before=$(cat "$VPS_BOOT_SSHD_DROPIN")
  systemctl() { printf '%s\n' "$*" >> "$systemctl_log"; }
  SSH_PORT=invalid
  USERNAME=alice

  ! lockdown_ssh >/dev/null 2>&1 || return 1
  [[ $(cat "$VPS_BOOT_SSHD_DROPIN") == "$before" ]] || return 1
  [[ ! -e $systemctl_log ]]
}

test_sshd_match_override_restores_previous_dropin() {
  local before systemctl_log="$TEST_ROOT/systemctl-match-override"
  reset_real_sshd_fixture || return 1
  cat >> "$VPS_BOOT_SSHD_CONFIG" <<'EOF'
Match User alice
  PasswordAuthentication yes
EOF
  write_previous_sshd_dropin || return 1
  before=$(cat "$VPS_BOOT_SSHD_DROPIN")
  systemctl() { printf '%s\n' "$*" >> "$systemctl_log"; }
  SSH_PORT=2222
  USERNAME=alice

  ! lockdown_ssh >/dev/null 2>&1 || return 1
  [[ $(cat "$VPS_BOOT_SSHD_DROPIN") == "$before" ]] || return 1
  [[ ! -e $systemctl_log ]]
}

test_sshd_root_match_override_restores_previous_dropin() {
  local before systemctl_log="$TEST_ROOT/systemctl-root-match-override"
  reset_real_sshd_fixture || return 1
  cat >> "$VPS_BOOT_SSHD_CONFIG" <<'EOF'
Match User root
  PermitRootLogin yes
EOF
  write_previous_sshd_dropin || return 1
  before=$(cat "$VPS_BOOT_SSHD_DROPIN")
  systemctl() { printf '%s\n' "$*" >> "$systemctl_log"; }
  SSH_PORT=2222
  USERNAME=alice

  ! lockdown_ssh >/dev/null 2>&1 || return 1
  [[ $(cat "$VPS_BOOT_SSHD_DROPIN") == "$before" ]] || return 1
  [[ ! -e $systemctl_log ]]
}

test_sshd_unexpected_listen_port_restores_previous_dropin() {
  local before systemctl_log="$TEST_ROOT/systemctl-listen-port"
  reset_real_sshd_fixture || return 1
  sed -i "/^HostKey/i ListenAddress 0.0.0.0:3333" "$VPS_BOOT_SSHD_CONFIG"
  write_previous_sshd_dropin || return 1
  before=$(cat "$VPS_BOOT_SSHD_DROPIN")
  systemctl() { printf '%s\n' "$*" >> "$systemctl_log"; }
  SSH_PORT=2222
  USERNAME=alice

  ! lockdown_ssh >/dev/null 2>&1 || return 1
  [[ $(cat "$VPS_BOOT_SSHD_DROPIN") == "$before" ]] || return 1
  [[ ! -e $systemctl_log ]]
}

test_sshd_loopback_only_listeners_restore_previous_dropin() {
  local before systemctl_log="$TEST_ROOT/systemctl-loopback-listeners"
  reset_real_sshd_fixture || return 1
  sed -i "/^HostKey/i ListenAddress 127.0.0.1:2222\nListenAddress [::1]:2222" \
    "$VPS_BOOT_SSHD_CONFIG"
  write_previous_sshd_dropin || return 1
  before=$(cat "$VPS_BOOT_SSHD_DROPIN")
  systemctl() { printf '%s\n' "$*" >> "$systemctl_log"; }
  SSH_PORT=2222
  USERNAME=alice

  ! lockdown_ssh >/dev/null 2>&1 || return 1
  [[ $(cat "$VPS_BOOT_SSHD_DROPIN") == "$before" ]] || return 1
  [[ ! -e $systemctl_log ]]
}

test_sshd_extra_port_restores_previous_dropin() {
  local before systemctl_log="$TEST_ROOT/systemctl-extra-port"
  reset_real_sshd_fixture || return 1
  sed -i "/^HostKey/i Port 3333" "$VPS_BOOT_SSHD_CONFIG"
  write_previous_sshd_dropin || return 1
  before=$(cat "$VPS_BOOT_SSHD_DROPIN")
  systemctl() { printf '%s\n' "$*" >> "$systemctl_log"; }
  SSH_PORT=2222
  USERNAME=alice

  ! lockdown_ssh >/dev/null 2>&1 || return 1
  [[ $(cat "$VPS_BOOT_SSHD_DROPIN") == "$before" ]] || return 1
  [[ ! -e $systemctl_log ]]
}

test_valid_sshd_policy_commits_and_reloads() {
  local systemctl_log="$TEST_ROOT/systemctl-valid"
  reset_real_sshd_fixture || return 1
  write_previous_sshd_dropin || return 1
  systemctl() { printf '%s\n' "$*" >> "$systemctl_log"; }
  SSH_PORT=2222
  USERNAME=alice

  lockdown_ssh || return 1
  grep -q '^Port 2222$' "$VPS_BOOT_SSHD_DROPIN" || return 1
  grep -q '^PermitRootLogin no$' "$VPS_BOOT_SSHD_DROPIN" || return 1
  [[ $(cat "$systemctl_log") == 'reload ssh.service' ]]
}

test_sshd_reload_failure_restores_and_reloads_previous_policy() {
  local before calls=0 systemctl_log="$TEST_ROOT/systemctl-reload-failure"
  reset_real_sshd_fixture || return 1
  write_previous_sshd_dropin || return 1
  before=$(cat "$VPS_BOOT_SSHD_DROPIN")
  systemctl() {
    calls=$((calls + 1))
    printf '%s\n' "$*" >> "$systemctl_log"
    (( calls > 1 ))
  }
  SSH_PORT=2222
  USERNAME=alice

  ! lockdown_ssh || return 1
  [[ $(cat "$VPS_BOOT_SSHD_DROPIN") == "$before" ]] || return 1
  [[ $(grep -c '^reload ssh.service$' "$systemctl_log") -eq 2 ]]
}

test_root_and_created_user_effective_policies() {
  local systemctl_log="$TEST_ROOT/systemctl-user-policies"
  reset_real_sshd_fixture || return 1
  systemctl() { printf '%s\n' "$*" >> "$systemctl_log"; }
  SSH_PORT=2222

  USERNAME=root
  apply_sshd_policy yes yes yes 0 || return 1
  [[ $(sshd_effective_value permitrootlogin) == yes ]] || return 1
  lockdown_ssh || return 1
  sshd_root_is_key_only "$(sshd_effective_value permitrootlogin)" || return 1

  USERNAME=alice
  apply_sshd_policy no yes yes 0 || return 1
  [[ $(sshd_effective_value permitrootlogin) == no ]] || return 1
  lockdown_ssh || return 1
  [[ $(sshd_effective_value permitrootlogin) == no ]]
}

test_lockdown_disables_password_methods_and_reloads() {
  local systemctl_log="$TEST_ROOT/systemctl-log"
  sshd() {
    if [[ $1 == -T ]]; then
      printf '%s\n' \
        'port 2222' \
        'listenaddress [::]:2222' \
        'listenaddress 0.0.0.0:2222' \
        'permitrootlogin no' \
        'passwordauthentication no' \
        'kbdinteractiveauthentication no'
    fi
    return 0
  }
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
  declare -F lockdown_ssh >/dev/null || return 1
  sshd() { return 1; }
  systemctl() { printf '%s\n' "$*" >> "$systemctl_log"; }
  SSH_PORT=2222
  USERNAME=alice
  ! lockdown_ssh || return 1
  [[ ! -e $systemctl_log ]]
}

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
  sshd() {
    if [[ $1 == -T ]]; then
      printf '%s\n' \
        'port 2222' \
        'listenaddress [::]:2222' \
        'listenaddress 0.0.0.0:2222' \
        'permitrootlogin without-password' \
        'passwordauthentication no' \
        'kbdinteractiveauthentication no'
    fi
    return 0
  }
  systemctl() { return 0; }
  SSH_PORT=2222
  USERNAME=root
  lockdown_ssh || return 1
  grep -q '^PermitRootLogin prohibit-password$' "$VPS_BOOT_SSHD_DROPIN" || return 1
  sshd_root_is_key_only prohibit-password || return 1
  sshd_root_is_key_only without-password || return 1
  ! sshd_root_is_key_only yes
}

test_install_caddy_never_calls_ufw() {
  # The firewall is bl_ufw's business; install_caddy must never open a port
  # itself. Guard the source directly so a future edit that slips in a
  # `ufw allow` call fails loudly here instead of only in a live check.
  declare -F install_caddy >/dev/null || return 1
  ! grep -qi 'ufw' <<< "$(declare -f install_caddy)"
}

test_check_caddy_reports_version_and_open_ufw_as_ok() {
  systemctl() { return 0; }
  caddy() { printf 'v2.8.4 h1:abcdefghi\n'; }
  ufw() {
    printf 'Status: active\n\n'
    printf '80/tcp                     ALLOW       Anywhere\n'
    printf '443/tcp                    ALLOW       Anywhere\n'
  }

  # Plain redirection, not `$(...)`: command substitution forks a subshell,
  # which would isolate check_caddy's ok()/note() counter updates away from
  # this function — same trap the "Mock by redefining" convention warns about.
  local outfile="$TEST_ROOT/check-caddy-ok-output"
  PASS=0; FAIL=0; WARN=0
  check_caddy > "$outfile"

  grep -q 'v2.8.4' "$outfile" || return 1
  (( FAIL == 0 )) || return 1
  (( WARN == 0 )) || return 1
  (( PASS == 2 ))
}

test_check_caddy_notes_closed_ufw_ports_without_failing() {
  # A closed firewall on a fresh install is the correct, deliberate state —
  # not a defect. The check must say so with `note`, and the run must still
  # exit 0 (only FAIL trips the non-zero exit).
  systemctl() { return 0; }
  caddy() { printf 'v2.8.4 h1:abcdefghi\n'; }
  ufw() { printf 'Status: active\n\n'; }

  local outfile="$TEST_ROOT/check-caddy-closed-output"
  PASS=0; FAIL=0; WARN=0
  check_caddy > "$outfile"

  grep -q 'v2.8.4' "$outfile" || return 1
  grep -q '80' "$outfile" || return 1
  grep -q '443' "$outfile" || return 1
  (( FAIL == 0 )) || return 1
  (( WARN == 1 )) || return 1
  (( PASS == 1 ))
}

test_check_caddy_fails_when_service_not_active() {
  systemctl() { return 1; }
  caddy() { printf 'v2.8.4 h1:abcdefghi\n'; }
  ufw() { printf 'Status: active\n\n'; }

  PASS=0; FAIL=0; WARN=0
  check_caddy >/dev/null

  (( FAIL == 1 ))
}

test_check_claude_reports_real_version() {
  claude() { [[ ${1:-} == --version ]] && printf '1.2.3\n'; }
  PASS=0; FAIL=0; WARN=0
  local out
  out=$(check_claude)
  [[ "$out" == *"claude 1.2.3"* ]] || return 1
  [[ "$out" != *'?'* ]]
}

# ── version parsing, against the strings the tools really print ─────────────
#
# Every stub below is a verbatim first line captured from the 23-component
# acceptance run on Ubuntu 24.04 (see
# docs/epics/epic-1-expand-toolchain-components/verification/). Parsers written
# against a guessed format pass vacuously; these do not.

test_check_claude_parses_the_upstream_version_line() {
  # Real output: "2.1.233 (Claude Code)". $NF is "Code)".
  claude() { [[ ${1:-} == --version ]] && printf '2.1.233 (Claude Code)\n'; }
  PASS=0; FAIL=0; WARN=0
  local out
  out=$(check_claude)
  [[ "$out" == *"claude 2.1.233"* ]] || return 1
  [[ "$out" != *'Code)'* ]] || return 1
  [[ "$out" != *'?'* ]]
}

test_hermes_user_script_leaves_the_invoking_cwd() {
  # `sudo -u <user> -H bash` sets HOME but inherits the *caller's* CWD, and the
  # caller is root sitting in /root (mode 700). The Hermes installer runs uv,
  # which probes "." for uv.toml and .venv, so the created-user acceptance run
  # died with:
  #   error: failed to query metadata of symlink `/root/.venv`:
  #   Permission denied (os error 13)
  # -- after 22 of 23 components had installed cleanly. The user-scope script
  # has to leave that directory before it runs anything.
  local home="$TEST_ROOT/hermes-home"
  mkdir -p "$home"
  # Stand in for the upstream installer: emit a script that reports its CWD.
  curl() { printf 'printf "cwd=%%s\\n" "$PWD"\n'; }
  local out
  out=$(cd "$TEST_ROOT" && HOME="$home" && eval "$(hermes_user_script)")
  [[ "$out" == "cwd=$home" ]]
}

test_install_hermes_runs_the_user_script() {
  # The seam only helps if install_hermes actually goes through it.
  declare -f install_hermes | grep -q 'hermes_user_script'
}

test_check_hermes_reports_a_bare_version() {
  # Real output: "Hermes Agent v0.20.2 (2026.8.16)" — printed whole it reads
  # "hermes Hermes Agent v0.20.2 (2026.8.16)".
  sudo() { printf 'Hermes Agent v0.20.2 (2026.8.16)\n'; }
  PASS=0; FAIL=0; WARN=0
  local outfile="$TEST_ROOT/check-hermes-output"
  USERNAME=root check_hermes > "$outfile" 2>&1
  grep -q 'hermes v0.20.2' "$outfile" || return 1
  ! grep -q 'Hermes Agent' "$outfile"
}

test_check_java_prints_exactly_one_line() {
  # Real output: 'openjdk version "25.0.3" 2026-04-21' on stderr. grep -o with
  # a lookbehind matches twice — once after the opening quote and once after
  # the closing one — so the date landed on a second, rail-less line.
  java() {
    [[ ${1:-} == -version ]] || return 1
    printf 'openjdk version "25.0.3" 2026-04-21\n' >&2
    printf 'OpenJDK Runtime Environment (build 25.0.3+9-2-24.04.2-Ubuntu)\n' >&2
  }
  javac() { printf 'javac 25.0.3\n'; }
  PASS=0; FAIL=0; WARN=0
  local outfile="$TEST_ROOT/check-java-output"
  check_java > "$outfile" 2>&1
  (( $(wc -l < "$outfile") == 1 )) || return 1
  grep -q 'java 25.0.3' "$outfile" || return 1
  ! grep -q '2026-04-21' "$outfile"
}

test_check_tools_reports_a_bare_tree_version() {
  # Real output: "tree v2.1.1 © 1996 - 2023 by Steve Baker, Thomas Moore, …" —
  # a whole copyright notice on the rail.
  jq() { printf 'jq-1.7\n'; }
  rg() { printf 'ripgrep 14.1.0\n'; }
  fd() { printf 'fdfind 9.0.0\n'; }
  htop() { printf 'htop 3.3.0\n'; }
  tree() {
    printf 'tree v2.1.1 %s 1996 - 2023 by Steve Baker, Thomas Moore, Francesc Rocher\n' '(c)'
  }
  PASS=0; FAIL=0; WARN=0
  local outfile="$TEST_ROOT/check-tools-output"
  check_tools > "$outfile" 2>&1
  grep -q 'tree v2.1.1' "$outfile" || return 1
  ! grep -q 'Steve Baker' "$outfile"
}

# check_rust's shims live at an absolute path, so the constants are
# env-overridable the same way LOG_FILE and STATE_DIR are.
make_rust_shims() {
  local rc=${1:-0} name
  mkdir -p "$CARGO_HOME_DIR/bin"
  for name in rustc cargo; do
    {
      printf '#!/usr/bin/env bash\n'
      # rustup's shim resolves the default toolchain out of RUSTUP_HOME; with
      # no RUSTUP_HOME it errors out even though the toolchain is installed.
      printf '[[ -n "${RUSTUP_HOME:-}" ]] || { echo "error: rustup could not choose a version" >&2; exit 1; }\n'
      printf '(( %s == 0 )) || exit %s\n' "$rc" "$rc"
      printf 'echo "%s 1.97.1 (8bab26f4f 2026-07-14)"\n' "$name"
    } > "$CARGO_HOME_DIR/bin/$name"
    chmod +x "$CARGO_HOME_DIR/bin/$name"
  done
}

test_check_rust_reports_versions_through_the_rustup_shims() {
  # The acceptance run printed "rust ? (cargo ?)": check_rust called the shims
  # with no RUSTUP_HOME, so rustup could not resolve the toolchain that was
  # sitting right there — and the "?" fallback reported it as a pass.
  make_rust_shims 0
  PASS=0; FAIL=0; WARN=0
  local outfile="$TEST_ROOT/check-rust-output"
  check_rust > "$outfile" 2>&1
  grep -q 'rust 1.97.1' "$outfile" || return 1
  grep -q 'cargo 1.97.1' "$outfile" || return 1
  [[ "$(cat "$outfile")" != *'?'* ]] || return 1
  (( FAIL == 0 && PASS == 1 ))
}

test_check_rust_fails_when_the_shims_cannot_report() {
  # A shim that cannot name a version is a broken toolchain, not a pass.
  make_rust_shims 1
  PASS=0; FAIL=0; WARN=0
  local outfile="$TEST_ROOT/check-rust-broken-output"
  check_rust > "$outfile" 2>&1
  grep -q '✗' "$outfile" || return 1
  (( FAIL == 1 ))
}

test_install_rust_and_check_rust_share_the_pinned_dirs() {
  # One definition of where rustup lives; install and check cannot drift apart.
  declare -f install_rust | grep -q 'RUSTUP_HOME_DIR' || return 1
  declare -f install_rust | grep -q 'CARGO_HOME_DIR' || return 1
  declare -f check_rust | grep -q 'RUSTUP_HOME_DIR' || return 1
  declare -f check_rust | grep -q 'CARGO_HOME_DIR'
}

test_agent_clis_registered_after_node() {
  local node_line codex_line gemini_line pi_line
  node_line=$(grep -n '^register node ' "$SCRIPT" | cut -d: -f1)
  codex_line=$(grep -n '^register codex ' "$SCRIPT" | cut -d: -f1)
  gemini_line=$(grep -n '^register gemini ' "$SCRIPT" | cut -d: -f1)
  pi_line=$(grep -n '^register pi ' "$SCRIPT" | cut -d: -f1)
  [[ -n $node_line && -n $codex_line && -n $gemini_line && -n $pi_line ]] || return 1
  (( node_line < codex_line )) || return 1
  (( node_line < gemini_line )) || return 1
  (( node_line < pi_line ))
}

test_no_pi_dev_installer_reference() {
  ! grep -q 'pi\.dev' "$SCRIPT"
}

test_readme_documents_new_defaults() {
  local enrollment_paragraph

  grep -q 'root-only' "$ROOT_DIR/README.md" || return 1
  grep -Eq 'Full install.*Passwordless sudo.*only when.*create a user' "$ROOT_DIR/README.md" || return 1
  grep -Eq 'Custom.*Passwordless sudo.*checkbox' "$ROOT_DIR/README.md" || return 1
  grep -q 'three minutes' "$ROOT_DIR/README.md" || return 1
  grep -Eq 'final SSH lockdown.*only when.*choose.*ok.*valid key' "$ROOT_DIR/README.md" || return 1
  grep -Eq 'Choosing .*skip.*missing or invalid key.*password authentication enabled' "$ROOT_DIR/README.md" || return 1
  grep -q 'PasswordAuthentication no' "$ROOT_DIR/README.md" || return 1
  grep -q 'KbdInteractiveAuthentication no' "$ROOT_DIR/README.md" || return 1
  grep -Fq 'check root <port>' "$ROOT_DIR/README.md" || return 1
  grep -Fq 'check <username> <port>' "$ROOT_DIR/README.md" || return 1
  grep -Eq '(unless|except when).*port 22' "$ROOT_DIR/README.md" || return 1

  # Keep the reload tied to the validated-key enrollment paragraph.
  enrollment_paragraph=$(awk 'BEGIN { RS="" } /authorized_keys/ && /valid SSH key/ { gsub(/\n/, " "); print; exit }' "$ROOT_DIR/README.md")
  [[ -n $enrollment_paragraph ]] || return 1
  grep -Eq 'only after.*authorized_keys.*valid SSH key' <<< "$enrollment_paragraph" || return 1
  grep -Eq 'Only then.*reload(s|ing)? .*ssh\.service' <<< "$enrollment_paragraph"
}

test_readme_lists_every_component_in_registry_order() {
  # The toolchain table drifts silently — adding a `register` line does not
  # touch README.md, and nothing else notices. Assert every component has a row,
  # in registry order, under its own group, and that the heading's count agrees.
  local key row prev=0
  for key in "${COMPONENTS[@]}"; do
    # BRE: "|" and "+" are literal, so the row can be matched as written.
    row=$(grep -n "^| ${COMPONENT_GROUP[$key]} | ${COMPONENT_NAME[$key]} |" \
      "$ROOT_DIR/README.md" | head -1 | cut -d: -f1)
    if [[ -z $row ]]; then
      printf 'README.md has no row for %s (%s)\n' "$key" "${COMPONENT_NAME[$key]}" >&2
      return 1
    fi
    if (( row <= prev )); then
      printf 'README.md row for %s is out of registry order\n' "$key" >&2
      return 1
    fi
    prev=$row
  done
  grep -q "^### Toolchain — ${#COMPONENTS[@]} components" "$ROOT_DIR/README.md"
}

test_cloud_cli_components_registered() {
  # vercel and neon install via npm, so they must land after node in registry
  # order (and thus in run order too).
  local key node_idx=-1 vercel_idx=-1 neon_idx=-1 hostinger_idx=-1 i=0
  for key in "${COMPONENTS[@]}"; do
    case "$key" in
      node) node_idx=$i ;;
      vercel) vercel_idx=$i ;;
      neon) neon_idx=$i ;;
      hostinger) hostinger_idx=$i ;;
    esac
    i=$((i + 1))
  done
  (( node_idx >= 0 && vercel_idx >= 0 && neon_idx >= 0 && hostinger_idx >= 0 )) || return 1
  (( vercel_idx > node_idx )) || return 1
  (( neon_idx > node_idx )) || return 1

  [[ "${COMPONENT_GROUP[vercel]:-}" == "cloud" ]] || return 1
  [[ "${COMPONENT_GROUP[neon]:-}" == "cloud" ]] || return 1
  [[ "${COMPONENT_GROUP[hostinger]:-}" == "cloud" ]] || return 1

  # check_neon must probe the neonctl binary (the package name), not the
  # shorter "neon" binary that ships alongside it.
  declare -f check_neon | grep -q 'neonctl' || return 1

  # vercel's sign-in hint must avoid the interactive browser callback, which
  # hangs on a headless box.
  [[ "${COMPONENT_SIGNIN[vercel]:-}" == *'--no-browser'* ]] || return 1

  # hostinger's token is account-wide (it can rebuild the VPS); the sign-in
  # hint must say so.
  [[ "${COMPONENT_SIGNIN[hostinger]:-}" == *'account-wide'* ]] || return 1

  # hostinger installs from a checksum-verified tarball, never an unverified
  # binary.
  declare -f install_hostinger | grep -q 'sha256sum' || return 1
}

run_test "sourcing vps-boot.sh does not run main" test_source_does_not_run_main
run_test "stdin execution runs main" test_stdin_execution_runs_main
run_test "step_run stops at the first failure" test_step_run_stops_at_first_failure
run_test "APT lock timeout fragment is temporary" test_apt_lock_timeout_fragment
run_test "APT setup failure removes candidate and final fragment" test_apt_setup_failure_removes_candidate_and_final
run_test "bl_update installs build-essential" test_bl_update_installs_build_essential
run_test "bl_unattended installs package and writes config" test_bl_unattended_installs_package_and_writes_config
run_test "bl_unattended cleans candidate after chmod failure" test_bl_unattended_cleans_candidate_after_chmod_failure
run_test "bl_unattended enables the timer without starting it now" test_bl_unattended_enables_timer_without_starting_it_now
run_test "wait_for_apt returns immediately when unlocked" test_wait_for_apt_returns_immediately_when_unlocked
run_test "wait_for_apt waits while the lock is held" test_wait_for_apt_waits_while_lock_is_held
run_test "wait_for_apt times out and reports" test_wait_for_apt_times_out_and_reports
run_test "wait_for_apt defaults its budget to APT_LOCK_TIMEOUT" test_wait_for_apt_defaults_budget_to_apt_lock_timeout_constant
run_test "wait_for_apt is a no-op when fuser is unavailable" test_wait_for_apt_is_a_noop_when_fuser_is_unavailable
run_test "wait_for_apt precedes every apt update/install call" test_wait_for_apt_precedes_every_apt_update_or_install_call
run_test "stop_apt_timers stops timers and services" test_stop_apt_timers_stops_timers_and_services
run_test "stop_apt_timers survives missing units" test_stop_apt_timers_survives_missing_units
run_test "restore_apt_timers starts both timers" test_restore_apt_timers_starts_both_timers
run_test "restore_apt_timers survives missing units" test_restore_apt_timers_survives_missing_units
run_test "cmd_install restores apt timers before the verifier" test_cmd_install_restores_apt_timers_before_the_verifier
run_test "do_check delegates the unattended assertion" test_do_check_delegates_the_unattended_assertion
run_test "unattended check names which half failed" test_do_check_unattended_names_which_half_failed
run_test "cmd_install stops apt timers before the first apt call" test_cmd_install_stops_apt_timers_before_first_apt_call
run_test "cmd_install restores apt timers on success" test_cmd_install_restores_apt_timers_on_success
run_test "cmd_install restores apt timers when a step fails" test_cmd_install_restores_apt_timers_when_a_step_fails
run_test "cmd_install arms timer restore before stopping timers" test_cmd_install_arms_timer_restore_before_stopping_timers
run_test "cmd_install restores apt timers on SIGHUP" test_cmd_install_restores_apt_timers_on_sighup
run_test "cmd_install restores apt timers on SIGTERM" test_cmd_install_restores_apt_timers_on_sigterm
run_test "cmd_install traps HUP/INT/TERM for cleanup" test_cmd_install_traps_hup_int_term_for_cleanup
run_test "signal handler disarms traps before cleanup" test_cmd_install_signal_handler_disarms_traps_before_cleanup
run_test "skip mode configures root" test_configure_user_mode_skip
run_test "create mode enables user creation" test_configure_user_mode_create
run_test "root Full install cmd_install flow filters user-only work" test_cmd_install_root_full_install_flow
run_test "created-user Custom cmd_install flow persists sudo" test_cmd_install_created_user_custom_flow
run_test "cmd_install runs bl_unattended between update and user" test_cmd_install_runs_bl_unattended_between_update_and_user
run_test "failed cmd_install flow cleans APT fragment" test_cmd_install_failure_cleans_apt_fragment
run_test "cmd_install arms APT cleanup before setup" test_cmd_install_arms_cleanup_before_apt_setup
run_test "root skips Docker group mutation" test_root_skips_docker_group_change
run_test "passwordless sudo defaults on and is root-filtered" test_sudo_nopasswd_is_default_and_root_filtered
run_test "passwordless sudo validates and installs" test_install_sudo_nopasswd_validates_and_installs
run_test "invalid sudoers leaves active rule unchanged" test_invalid_sudoers_does_not_replace_active_rule
run_test "passwordless sudo cleans candidate after chmod failure" test_sudo_nopasswd_cleans_candidate_after_chmod_failure
run_test "SSH drop-in has one value per managed key" test_sshd_dropin_has_single_managed_values
run_test "SSH syntax failure restores previous drop-in" test_sshd_syntax_failure_restores_previous_dropin
run_test "SSH Match override restores previous drop-in" test_sshd_match_override_restores_previous_dropin
run_test "SSH root Match override restores previous drop-in" test_sshd_root_match_override_restores_previous_dropin
run_test "SSH unexpected ListenAddress port restores previous drop-in" test_sshd_unexpected_listen_port_restores_previous_dropin
run_test "SSH loopback-only listeners restore previous drop-in" test_sshd_loopback_only_listeners_restore_previous_dropin
run_test "SSH extra port restores previous drop-in" test_sshd_extra_port_restores_previous_dropin
run_test "valid SSH policy commits and reloads" test_valid_sshd_policy_commits_and_reloads
run_test "SSH reload failure restores previous policy" test_sshd_reload_failure_restores_and_reloads_previous_policy
run_test "root and created-user effective SSH policies" test_root_and_created_user_effective_policies
run_test "SSH lockdown disables passwords and reloads" test_lockdown_disables_password_methods_and_reloads
run_test "invalid SSH config is not reloaded" test_invalid_sshd_config_is_not_reloaded
run_test "SSH lockdown stops after drop-in write failure" test_lockdown_stops_when_dropin_write_fails
run_test "effective SSH values come from sshd -T" test_sshd_effective_value_reads_sshd_T
run_test "root lockdown is key-only" test_root_lockdown_is_key_only
run_test "install_caddy never calls ufw" test_install_caddy_never_calls_ufw
run_test "check_caddy reports version and open UFW ports as ok" test_check_caddy_reports_version_and_open_ufw_as_ok
run_test "check_caddy notes closed UFW ports without failing" test_check_caddy_notes_closed_ufw_ports_without_failing
run_test "check_caddy fails when the service is not active" test_check_caddy_fails_when_service_not_active
run_test "check_claude reports a real version" test_check_claude_reports_real_version
run_test "check_claude parses the upstream version line" test_check_claude_parses_the_upstream_version_line
run_test "check_java prints exactly one line" test_check_java_prints_exactly_one_line
run_test "hermes user script leaves the invoking cwd" test_hermes_user_script_leaves_the_invoking_cwd
run_test "install_hermes runs the user script" test_install_hermes_runs_the_user_script
run_test "check_hermes reports a bare version" test_check_hermes_reports_a_bare_version
run_test "check_tools reports a bare tree version" test_check_tools_reports_a_bare_tree_version
run_test "check_rust reports versions through the rustup shims" test_check_rust_reports_versions_through_the_rustup_shims
run_test "check_rust fails when the shims cannot report" test_check_rust_fails_when_the_shims_cannot_report
run_test "install_rust and check_rust share the pinned dirs" test_install_rust_and_check_rust_share_the_pinned_dirs
run_test "codex, gemini and pi register after node" test_agent_clis_registered_after_node
run_test "no pi.dev installer reference remains" test_no_pi_dev_installer_reference
run_test "README documents new defaults" test_readme_documents_new_defaults
run_test "registry entries name real functions, scope and group" test_registry_entries_are_well_formed
run_test "java LTS probe only probes LTS majors" test_probe_java_lts_jdk_only_probes_lts_majors
run_test "java LTS probe fails when none installable" test_probe_java_lts_jdk_fails_when_none_installable
run_test "check_java redirects stderr for the version string" test_check_java_reports_version_via_stderr_redirect
run_test "check_java fails on a JRE-only box" test_check_java_fails_without_javac
run_test "install_rust uses non-interactive pinned flags" test_install_rust_uses_noninteractive_pinned_flags
run_test "check_rust reports both rustc and cargo" test_check_rust_reports_both_rustc_and_cargo_versions
run_test "install_uv pins its install dir" test_install_uv_pins_install_dir
run_test "check_uv reports its version" test_check_uv_reports_version
run_test "check_uv fails when uv is missing" test_check_uv_fails_when_missing
run_test "README lists every component in registry order" test_readme_lists_every_component_in_registry_order
run_test "cloud CLI components are registered correctly" test_cloud_cli_components_registered
run_test "vis_len counts glyphs as one column" test_vis_len_counts_glyphs_as_one_column
run_test "install-mode counts line fits 80 columns" test_install_mode_counts_line_fits_80_columns
run_test "group counts follow COMPONENT_GROUPS order" test_component_group_counts_follow_group_order
run_test "Full install keys are computed from the registry" test_full_install_keys_are_registry_computed
run_test "Install mode label names no tools" test_install_mode_label_names_no_tools
run_test "full selection summary collapses to group counts" test_selection_summary_full_collapses_to_group_counts
run_test "partial selection summary lists skipped names" test_selection_summary_partial_lists_skipped_names
run_test "selection summary lists the shorter half" test_selection_summary_lists_selected_when_it_is_shorter
run_test "full selection summary never exceeds its budget" test_selection_summary_full_never_exceeds_its_budget
run_test "full selection summary keeps every group when it fits" test_selection_summary_full_keeps_every_group_when_it_fits
run_test "full selection summary degrades to the count alone" test_selection_summary_full_degrades_to_the_count_alone
run_test "selection summary never exceeds its budget" test_selection_summary_never_exceeds_its_budget
run_test "grid columns degrade on narrow terminals" test_msel_columns_degrade_on_narrow_terminals
run_test "grid fits an 80x24 terminal" test_msel_grid_fits_an_80x24_terminal
run_test "grid degrades to fewer columns at 60" test_msel_grid_degrades_to_fewer_columns_at_60
run_test "grid rows follow registry group order" test_msel_grid_groups_rows_in_registry_group_order
run_test "grid header counts track a and n" test_msel_header_counts_track_select_all_and_none
run_test "grid navigation is two-dimensional" test_msel_navigation_is_two_dimensional
run_test "grid redraw count matches what was printed" test_msel_redraw_count_matches_what_was_printed
run_test "grid collect writes selected keys" test_msel_collect_writes_selected_keys
run_test "empty Custom selection runs the baseline only" test_cmd_install_empty_selection_runs_baseline_only
run_test "no old install-mode name remains" test_no_old_mode_name_references_remain

printf '%s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
(( FAIL_COUNT == 0 ))
