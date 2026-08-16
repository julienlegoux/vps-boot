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
run_test "README documents new defaults" test_readme_documents_new_defaults

printf '%s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
(( FAIL_COUNT == 0 ))
