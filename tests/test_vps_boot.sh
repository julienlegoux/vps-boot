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
  grep -q 'RUSTUP_HOME=/usr/local/rustup' <<< "$src" || return 1
  grep -q 'CARGO_HOME=/usr/local/cargo' <<< "$src"
}

test_check_rust_reports_both_rustc_and_cargo_versions() {
  # A half-installed toolchain where cargo is missing (but rustc is present)
  # is the failure worth catching.
  local src
  src=$(declare -f check_rust)
  grep -q 'rustc' <<< "$src" || return 1
  grep -q 'cargo' <<< "$src" || return 1
  grep -q '/usr/local/cargo/bin' <<< "$src"
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

test_cmd_install_root_quickstart_flow() {
  local expected="" key
  local text_log="$TEST_ROOT/root-text-prompts"
  local password_log="$TEST_ROOT/root-password-prompts"
  FLOW_TRACE="$TEST_ROOT/root-flow-trace"
  prepare_stubbed_install_flow || return 1
  prompt_radio() {
    local label=$1 outvar=$2 value
    case "$label" in
      "User account") value=skip ;;
      "Install mode") value=QuickStart ;;
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
  [[ $(cat "$VPS_BOOT_STATE_DIR/components") == sudo_nopasswd ]]
}

test_cmd_install_runs_bl_unattended_between_update_and_user() {
  FLOW_TRACE="$TEST_ROOT/order-flow-trace"
  prepare_stubbed_install_flow || return 1
  prompt_radio() {
    local label=$1 outvar=$2 value
    case "$label" in
      "User account") value=create ;;
      "Install mode") value=QuickStart ;;
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

test_cmd_install_failure_cleans_apt_fragment() {
  FLOW_TRACE="$TEST_ROOT/failing-flow-trace"
  prepare_stubbed_install_flow || return 1
  prompt_radio() {
    local label=$1 outvar=$2 value
    case "$label" in
      "User account") value=skip ;;
      "Install mode") value=QuickStart ;;
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
      "Install mode") value=QuickStart ;;
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

test_check_claude_reports_real_version() {
  claude() { [[ ${1:-} == --version ]] && printf '1.2.3\n'; }
  PASS=0; FAIL=0; WARN=0
  local out
  out=$(check_claude)
  [[ "$out" == *"claude 1.2.3"* ]] || return 1
  [[ "$out" != *'?'* ]]
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
  grep -Eq 'QuickStart.*Passwordless sudo.*only when.*create a user' "$ROOT_DIR/README.md" || return 1
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
run_test "skip mode configures root" test_configure_user_mode_skip
run_test "create mode enables user creation" test_configure_user_mode_create
run_test "root QuickStart cmd_install flow filters user-only work" test_cmd_install_root_quickstart_flow
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
run_test "check_claude reports a real version" test_check_claude_reports_real_version
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
run_test "cloud CLI components are registered correctly" test_cloud_cli_components_registered

printf '%s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
(( FAIL_COUNT == 0 ))
