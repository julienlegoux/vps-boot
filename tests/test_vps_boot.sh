#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT_DIR/vps-boot.sh"
PASS_COUNT=0
FAIL_COUNT=0
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
export VPS_BOOT_LOG_FILE="$TEST_ROOT/vps-boot.log"
export VPS_BOOT_APT_LOCK_CONFIG="$TEST_ROOT/99-vps-boot-lock-timeout"
export VPS_BOOT_SUDOERS_DIR="$TEST_ROOT/sudoers.d"
export VPS_BOOT_SSHD_CONFIG="$TEST_ROOT/sshd_config"
export VPS_BOOT_SSHD_DROPIN="$TEST_ROOT/sshd_config.d/00-vps-boot.conf"
mkdir -p "$(dirname "$VPS_BOOT_SSHD_DROPIN")"
printf 'Include %s/*.conf\n' "$(dirname "$VPS_BOOT_SSHD_DROPIN")" > "$VPS_BOOT_SSHD_CONFIG"

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
  sshd() { return 0; }
  systemctl() { return 0; }
  SSH_PORT=2222
  USERNAME=root
  lockdown_ssh || return 1
  grep -q '^PermitRootLogin prohibit-password$' "$VPS_BOOT_SSHD_DROPIN" || return 1
  sshd_root_is_key_only prohibit-password || return 1
  sshd_root_is_key_only without-password || return 1
  ! sshd_root_is_key_only yes
}

run_test "sourcing vps-boot.sh does not run main" test_source_does_not_run_main
run_test "step_run stops at the first failure" test_step_run_stops_at_first_failure
run_test "APT lock timeout fragment is temporary" test_apt_lock_timeout_fragment
run_test "skip mode configures root" test_configure_user_mode_skip
run_test "create mode enables user creation" test_configure_user_mode_create
run_test "root skips Docker group mutation" test_root_skips_docker_group_change
run_test "passwordless sudo defaults on and is root-filtered" test_sudo_nopasswd_is_default_and_root_filtered
run_test "passwordless sudo validates and installs" test_install_sudo_nopasswd_validates_and_installs
run_test "invalid sudoers leaves active rule unchanged" test_invalid_sudoers_does_not_replace_active_rule
run_test "passwordless sudo cleans candidate after chmod failure" test_sudo_nopasswd_cleans_candidate_after_chmod_failure
run_test "SSH drop-in has one value per managed key" test_sshd_dropin_has_single_managed_values
run_test "SSH lockdown disables passwords and reloads" test_lockdown_disables_password_methods_and_reloads
run_test "invalid SSH config is not reloaded" test_invalid_sshd_config_is_not_reloaded
run_test "SSH lockdown stops after drop-in write failure" test_lockdown_stops_when_dropin_write_fails
run_test "effective SSH values come from sshd -T" test_sshd_effective_value_reads_sshd_T
run_test "root lockdown is key-only" test_root_lockdown_is_key_only

printf '%s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
(( FAIL_COUNT == 0 ))
