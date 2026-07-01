#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT_DIR/vps-boot.sh"
PASS_COUNT=0
FAIL_COUNT=0
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
export VPS_BOOT_LOG_FILE="$TEST_ROOT/vps-boot.log"

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

run_test "sourcing vps-boot.sh does not run main" test_source_does_not_run_main
run_test "step_run stops at the first failure" test_step_run_stops_at_first_failure

printf '%s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
(( FAIL_COUNT == 0 ))
