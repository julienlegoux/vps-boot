#!/usr/bin/env bash
# vps-boot.sh — resumable Ubuntu 26.04 amd64 hardening + dev toolchain
# Usage: sudo ./vps-boot.sh install [username] [port]
#        sudo ./vps-boot.sh harden  [username]
#        sudo ./vps-boot.sh check   [username] [port]
#        sudo ./vps-boot.sh --help
#
# Or via curl:
#   curl -fsSL https://raw.githubusercontent.com/julienlegoux/vps-boot/main/vps-boot.sh | sudo bash -s install

set -euo pipefail

# ════════════════════════════════════════════════════════════════════════════
# Constants
# ════════════════════════════════════════════════════════════════════════════

readonly PORT_MIN=10000
readonly VPS_BOOT_VERSION=0.1.0
readonly PORT_MAX=65535
readonly LOG_FILE="${VPS_BOOT_LOG_FILE:-/var/log/vps-boot.log}"
readonly APT_LOCK_TIMEOUT=180
readonly APT_LOCK_CONFIG="${VPS_BOOT_APT_LOCK_CONFIG:-/etc/apt/apt.conf.d/99-vps-boot-lock-timeout}"
readonly UNATTENDED_UPGRADES_CONFIG="${VPS_BOOT_UNATTENDED_UPGRADES_CONFIG:-/etc/apt/apt.conf.d/99vps-boot-unattended}"
readonly SUDOERS_DIR="${VPS_BOOT_SUDOERS_DIR:-/etc/sudoers.d}"
readonly SSHD_CONFIG="${VPS_BOOT_SSHD_CONFIG:-/etc/ssh/sshd_config}"
readonly SSHD_DROPIN="${VPS_BOOT_SSHD_DROPIN:-/etc/ssh/sshd_config.d/00-vps-boot.conf}"
readonly STATE_DIR="${VPS_BOOT_STATE_DIR:-/etc/vps-boot}"
readonly STATE_FILE="$STATE_DIR/components"
readonly STATE_CONFIG="$STATE_DIR/config"
readonly JOURNAL_DIR="$STATE_DIR/journal"
readonly PYTHON_HOME="${VPS_BOOT_PYTHON_HOME:-/opt/vps-boot/python}"
readonly PYTHON_BIN="${VPS_BOOT_PYTHON_BIN:-/usr/local/bin/python}"
# The canonical remote invocation. Shared by --help and by the hint `harden`
# prints when there is no script on disk to re-run — under `curl | sudo bash`
# $0 is "bash", so telling the operator to run "$0 harden" is useless.
readonly REMOTE_URL="https://raw.githubusercontent.com/julienlegoux/vps-boot/develop/vps-boot.sh"
# rustup is installed system-wide rather than under $HOME. Both install_rust
# and check_rust read these, so the two cannot point at different trees.
readonly RUSTUP_HOME_DIR="${VPS_BOOT_RUSTUP_HOME:-/usr/local/rustup}"
readonly CARGO_HOME_DIR="${VPS_BOOT_CARGO_HOME:-/usr/local/cargo}"

# ANSI colors — disabled if stdout isn't a tty
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_ORANGE=$'\033[38;5;208m'
  C_GREEN=$'\033[32m'
  C_RED=$'\033[31m'
  C_YELLOW=$'\033[33m'
  C_CYAN=$'\033[36m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_ORANGE=""
  C_GREEN=""; C_RED=""; C_YELLOW=""; C_CYAN=""
fi

# ════════════════════════════════════════════════════════════════════════════
# UI library
# ════════════════════════════════════════════════════════════════════════════

banner() {
  printf '%s' "$C_CYAN"
  cat <<'BANNER'

   ██╗   ██╗██████╗ ███████╗      ██████╗  ██████╗  ██████╗ ████████╗
   ██║   ██║██╔══██╗██╔════╝      ██╔══██╗██╔═══██╗██╔═══██╗╚══██╔══╝
   ██║   ██║██████╔╝███████╗█████╗██████╔╝██║   ██║██║   ██║   ██║
   ╚██╗ ██╔╝██╔═══╝ ╚════██║╚════╝██╔══██╗██║   ██║██║   ██║   ██║
    ╚████╔╝ ██║     ███████║      ██████╔╝╚██████╔╝╚██████╔╝   ██║
     ╚═══╝  ╚═╝     ╚══════╝      ╚═════╝  ╚═════╝  ╚═════╝    ╚═╝
BANNER
  printf '%s' "$C_RESET"
  printf '   %sone-shot Ubuntu hardening + dev toolchain%s\n\n' "$C_DIM" "$C_RESET"
}

# term_cols / term_lines — terminal geometry with a sane fallback. Every
# rendering decision (column count, cursor-up distance) goes through these so a
# test can stub them and so a missing/odd `tput` can never produce a bad number.
term_cols() {
  local c
  c=$(tput cols 2>/dev/null || echo 80)
  [[ "$c" =~ ^[0-9]+$ ]] && (( c > 0 )) || c=80
  printf '%s' "$c"
}

term_lines() {
  local l
  l=$(tput lines 2>/dev/null || echo 24)
  [[ "$l" =~ ^[0-9]+$ ]] && (( l > 0 )) || l=24
  printf '%s' "$l"
}

# vis_len "text" — visible column count. ${#s} counts *bytes* under the C
# locale, and every glyph in this script's vocabulary is multi-byte, so any
# width decision on a string that might contain one goes through here.
vis_len() {
  local s=$1
  s=${s//·/.}; s=${s//—/-}; s=${s//─/-}
  s=${s//↑/^}; s=${s//↓/v}; s=${s//←/<}; s=${s//→/>}
  s=${s//│/|}; s=${s//◇/o}; s=${s//◆/O}
  s=${s//◉/x}; s=${s//◌/.}; s=${s//●/*}; s=${s//○/o}; s=${s//›/>}
  printf '%s' "${#s}"
}

# section "Title" — opens a new section with diamond + orange title + rule
section() {
  local title=$1
  local term_w
  term_w=$(term_cols)
  local prefix_len=4   # "◇  " is 3 visible chars + 1 trailing space
  local title_len=${#title}
  local fill=$(( term_w - prefix_len - title_len - 2 ))
  (( fill < 4 )) && fill=4
  (( fill > 60 )) && fill=60

  local rule=""
  local i
  for ((i=0; i<fill; i++)); do rule+="─"; done

  printf '\n%s◇%s  %s%s%s%s  %s%s%s\n' \
    "$C_ORANGE" "$C_RESET" \
    "$C_BOLD$C_ORANGE" "$title" "$C_RESET" "" \
    "$C_DIM" "$rule" "$C_RESET"
}

# rail — empty connector line
rail() { printf '%s│%s\n' "$C_DIM" "$C_RESET"; }

# body "text" — indented body line under the rail
body() { printf '%s│%s  %s\n' "$C_DIM" "$C_RESET" "$1"; }

# done_section "Title" — section header with completed-diamond style
done_section() {
  printf '\n%s◆%s  %s%s%s\n' \
    "$C_GREEN" "$C_RESET" \
    "$C_BOLD" "$1" "$C_RESET"
}

# step_run "Label" cmd args... — runs cmd, redirects output to log,
#   prints ✓ on success or ✗ + tail on failure
step_run() {
  local label=$1; shift
  local pad=42
  local label_len=${#label}
  local dots=$(( pad - label_len - 4 ))
  (( dots < 1 )) && dots=1
  local dotstr=""
  local i; for ((i=0; i<dots; i++)); do dotstr+="."; done

  printf '%s│%s  %s◇%s  %s ' "$C_DIM" "$C_RESET" "$C_ORANGE" "$C_RESET" "$label"
  printf '%s%s%s ' "$C_DIM" "$dotstr" "$C_RESET"
  printf '%s…%s' "$C_DIM" "$C_RESET"

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
}

# ok / ko / note — verifier status indicators (used in cmd_check)
ok()   { printf '%s│%s  %s✓%s  %s\n' "$C_DIM" "$C_RESET" "$C_GREEN"  "$C_RESET" "$1"; PASS=$((PASS+1)); }
ko()   { printf '%s│%s  %s✗%s  %s\n' "$C_DIM" "$C_RESET" "$C_RED"    "$C_RESET" "$1"; FAIL=$((FAIL+1)); }
note() { printf '%s│%s  %s!%s  %s\n' "$C_DIM" "$C_RESET" "$C_YELLOW" "$C_RESET" "$1"; WARN=$((WARN+1)); }

# die "msg" — fatal error
die() {
  printf '\n%s✗ %s%s\n\n' "$C_RED" "$1" "$C_RESET" >&2
  exit 1
}

# warn "msg" — non-fatal warning
warn() {
  printf '%s! %s%s\n' "$C_YELLOW" "$1" "$C_RESET" >&2
}

# prompt_text "label" out_var ["default"]
# Reads from /dev/tty so it works under `curl | sudo bash`. Writes the
# entered value to the named variable — do NOT call via $(...) because the
# UI rendering goes to stdout and would be captured.
prompt_text() {
  local label=$1
  local out_var=$2
  local default=${3:-}
  local input prompt_str

  printf '\n%s◇%s  %s%s%s\n' "$C_ORANGE" "$C_RESET" "$C_BOLD" "$label" "$C_RESET"
  # \001…\002 mark colour codes zero-width so readline's edge-stop respects the prompt.
  prompt_str=$(printf '\001%s\002│\001%s\002  \001%s\002›\001%s\002 ' \
    "$C_DIM" "$C_RESET" "$C_CYAN" "$C_RESET")

  if [[ -n "$default" ]]; then
    IFS= read -r -e -i "$default" -p "$prompt_str" input < /dev/tty
  else
    IFS= read -r -e -p "$prompt_str" input < /dev/tty
  fi

  printf -v "$out_var" '%s' "${input:-$default}"
}

# prompt_password "label" out_var
# Writes the password to the named variable. Do NOT call via $(...).
prompt_password() {
  local label=$1
  local out_var=$2
  local pw1 pw2

  while :; do
    printf '\n%s◇%s  %s%s%s\n' "$C_ORANGE" "$C_RESET" "$C_BOLD" "$label" "$C_RESET"
    printf '%s│%s  %s›%s ' "$C_DIM" "$C_RESET" "$C_CYAN" "$C_RESET"
    IFS= read -r -s pw1 < /dev/tty
    printf '\n'
    if [[ -z "$pw1" ]]; then
      printf '%s│%s  %s! password cannot be empty%s\n' "$C_DIM" "$C_RESET" "$C_YELLOW" "$C_RESET"
      continue
    fi
    printf '%s│%s  %sconfirm%s\n' "$C_DIM" "$C_RESET" "$C_DIM" "$C_RESET"
    printf '%s│%s  %s›%s ' "$C_DIM" "$C_RESET" "$C_CYAN" "$C_RESET"
    IFS= read -r -s pw2 < /dev/tty
    printf '\n'
    if [[ "$pw1" != "$pw2" ]]; then
      printf '%s│%s  %s! passwords did not match — try again%s\n' "$C_DIM" "$C_RESET" "$C_YELLOW" "$C_RESET"
      continue
    fi
    break
  done

  printf -v "$out_var" '%s' "$pw1"
}

# prompt_radio "label" out_var "option1|desc1[|desc1b]" "option2|desc2" ...
# Selected option key is stored in the named variable. An optional third field
# renders as a dim continuation line under the description — that is how the
# install-mode option carries its per-group counts without a second prompt.
# Keys are padded to a common width so descriptions line up in a column.
prompt_radio() {
  local label=$1
  local out_var=$2
  shift 2
  local -a keys=()
  local -a descs=()
  local -a descs2=()
  local opt key rest desc desc2
  for opt in "$@"; do
    key=${opt%%|*}
    rest=${opt#*|}
    [[ "$rest" == "$opt" ]] && rest=""
    desc=${rest%%|*}
    desc2=${rest#*|}
    [[ "$desc2" == "$rest" ]] && desc2=""
    keys+=("$key")
    descs+=("$desc")
    descs2+=("$desc2")
  done
  local n=${#keys[@]}
  local current=0

  # keyw: widest key, for the description column. rows: what _radio_draw
  # actually prints — never assume one row per option, the continuation lines
  # add rows and the cursor-up must match.
  local keyw=0 i term_w
  term_w=$(term_cols)
  for ((i=0; i<n; i++)); do
    if (( ${#keys[i]} > keyw )); then keyw=${#keys[i]}; fi
  done

  # Continuation lines align under the description column when there is room,
  # slide left when there is not, and are dropped entirely when even the
  # minimum indent would overflow — a wrapped line loses its rail prefix and
  # breaks the left border. `rows` counts only what will actually be printed,
  # because it is the redraw's cursor-up distance.
  local -a indent2=()
  local rows=0 want fits
  for ((i=0; i<n; i++)); do
    rows=$(( rows + 1 ))
    want=0
    if [[ -n "${descs2[i]}" ]]; then
      fits=$(( term_w - 6 - $(vis_len "${descs2[i]}") ))
      if (( fits < 2 )); then
        descs2[i]=""
      else
        want=$(( keyw + 2 ))
        (( fits < want )) && want=$fits
        rows=$(( rows + 1 ))
      fi
    fi
    indent2+=("$want")
  done

  printf '\n%s◇%s  %s%s%s\n' "$C_ORANGE" "$C_RESET" "$C_BOLD" "$label" "$C_RESET"
  printf '%s│%s  %s(↑/↓ to move, enter to confirm)%s\n' "$C_DIM" "$C_RESET" "$C_DIM" "$C_RESET"

  _radio_draw() {
    local i
    for ((i=0; i<n; i++)); do
      printf '\033[2K'
      printf '%s│%s  ' "$C_DIM" "$C_RESET"
      if (( i == current )); then
        printf '%s●%s %s%-*s%s' "$C_CYAN" "$C_RESET" "$C_BOLD" "$keyw" "${keys[i]}" "$C_RESET"
      else
        printf '%s○%s %-*s' "$C_DIM" "$C_RESET" "$keyw" "${keys[i]}"
      fi
      if [[ -n "${descs[i]}" ]]; then
        printf '   %s%s%s' "$C_DIM" "${descs[i]}" "$C_RESET"
      fi
      printf '\n'
      if [[ -n "${descs2[i]}" ]]; then
        printf '\033[2K'
        printf '%s│%s  %*s   %s%s%s\n' \
          "$C_DIM" "$C_RESET" "${indent2[i]}" "" "$C_DIM" "${descs2[i]}" "$C_RESET"
      fi
    done
  }

  _radio_draw

  local k rest2
  while :; do
    IFS= read -rsn1 k < /dev/tty || break
    case "$k" in
      $'\033')
        IFS= read -rsn2 -t 0.05 rest2 < /dev/tty || rest2=""
        case "$rest2" in
          '[A') current=$(( (current - 1 + n) % n )) ;;
          '[B') current=$(( (current + 1) % n )) ;;
        esac
        ;;
      '')
        break  # enter
        ;;
      'k') current=$(( (current - 1 + n) % n )) ;;
      'j') current=$(( (current + 1) % n )) ;;
    esac

    # redraw — move up by the rows actually printed, not by the option count
    printf '\033[%dA' "$rows"
    _radio_draw
  done

  # collapse: clear hint + options, reprint just the chosen value
  printf '\033[%dA\033[J' "$(( rows + 1 ))"
  printf '%s│%s  %s●%s %s%s%s\n' "$C_DIM" "$C_RESET" "$C_GREEN" "$C_RESET" "$C_BOLD" "${keys[current]}" "$C_RESET"

  printf -v "$out_var" '%s' "${keys[current]}"
}

# ── grouped grid multi-select ───────────────────────────────────────────────
#
# prompt_multiselect "label" "key|name|desc|default|group" ...
#   default is 1 (checked) or 0 (unchecked); group is one of COMPONENT_GROUPS.
#   Selected keys land in PROMPT_MSEL_RESULT.
#
# Options are laid out as a grid: the group name in a left gutter, then up to
# three columns of `MSEL_CELL_W`. Twenty-three components become ~9 rows instead
# of 23, which is what keeps the whole block on an 80×24 screen.
#
# The state lives in MSEL_* globals rather than in locals so the rendering and
# navigation can be unit-tested without a tty. Two invariants matter:
#   * every visible line is built into MSEL_LINES, so the redraw's cursor-up
#     distance is the number of lines that were actually printed — never a
#     guess of one row per option, which is what corrupted the old picker once
#     the block outgrew the screen;
#   * that distance is additionally clamped to the terminal height, so a block
#     that did scroll only redraws the part still on screen.
PROMPT_MSEL_RESULT=()
MSEL_LABEL=""
MSEL_KEYS=(); MSEL_NAMES=(); MSEL_DESCS=(); MSEL_SEL=(); MSEL_GROUPS=()
MSEL_ROW_START=(); MSEL_ROW_LEN=(); MSEL_ROW_LABEL=()
MSEL_ROW_OF=(); MSEL_COL_OF=()
MSEL_LINES=()
MSEL_CURRENT=0
MSEL_COLS=3
MSEL_GUTTER=10
MSEL_CELL_W=21   # "›◉ Passwordless sudo " — marker + glyph + space + 17 + pad
MSEL_CELL=21

# msel_parse "label" "key|name|desc|default|group" ...
# Fills the MSEL_* arrays in COMPONENT_GROUPS order (stable within a group), so
# the flat index is also the display position and navigation needs no mapping.
msel_parse() {
  MSEL_LABEL=$1
  shift
  MSEL_KEYS=(); MSEL_NAMES=(); MSEL_DESCS=(); MSEL_SEL=(); MSEL_GROUPS=()
  local -a keys=() names=() descs=() defs=() groups=()
  local opt key name desc def group
  for opt in "$@"; do
    IFS='|' read -r key name desc def group <<<"$opt"
    keys+=("$key")
    names+=("$name")
    descs+=("$desc")
    defs+=("${def:-0}")
    groups+=("${group:-${COMPONENT_GROUP[$key]:-other}}")
  done

  local g i known
  for g in "${COMPONENT_GROUPS[@]}" "__rest__"; do
    for ((i=0; i<${#keys[@]}; i++)); do
      if [[ "$g" == "__rest__" ]]; then
        known=0
        case " ${COMPONENT_GROUPS[*]} " in *" ${groups[i]} "*) known=1 ;; esac
        (( known )) && continue
      elif [[ "${groups[i]}" != "$g" ]]; then
        continue
      fi
      MSEL_KEYS+=("${keys[i]}")
      MSEL_NAMES+=("${names[i]}")
      MSEL_DESCS+=("${descs[i]}")
      MSEL_SEL+=("${defs[i]}")
      MSEL_GROUPS+=("${groups[i]}")
    done
  done
  MSEL_CURRENT=0
  return 0
}

# msel_columns <width> — how many component columns fit, 1 to 3.
# 3 + gutter + 3×21 = 76 at the default gutter, so 80 gets three columns and
# 60 degrades to two rather than wrapping.
msel_columns() {
  local width=${1:-80}
  local avail=$(( width - 3 - MSEL_GUTTER ))
  local c=$(( avail / MSEL_CELL_W ))
  (( c > 3 )) && c=3
  (( c < 1 )) && c=1
  printf '%s' "$c"
}

msel_layout() {
  local g w=0
  for g in "${COMPONENT_GROUPS[@]}"; do
    if (( ${#g} > w )); then w=${#g}; fi
  done
  MSEL_GUTTER=$(( w + 1 ))

  # Never name this local `width`: term_cols is dynamically scoped, so a local
  # of the same name would shadow whatever the caller's stub reads.
  local term_w
  term_w=$(term_cols)
  MSEL_COLS=$(msel_columns "$term_w")

  # Single column on a very narrow terminal still has to fit; shrink the cell
  # (and truncate names to match) rather than wrap the line.
  MSEL_CELL=$MSEL_CELL_W
  local room=$(( term_w - 3 - MSEL_GUTTER ))
  if (( MSEL_COLS == 1 && room < MSEL_CELL_W )); then
    MSEL_CELL=$room
    (( MSEL_CELL < 8 )) && MSEL_CELL=8
  fi

  MSEL_ROW_START=(); MSEL_ROW_LEN=(); MSEL_ROW_LABEL=()
  MSEL_ROW_OF=(); MSEL_COL_OF=()
  local n=${#MSEL_KEYS[@]} i=0 r=0 gend len c first label
  while (( i < n )); do
    label=${MSEL_GROUPS[i]}
    gend=$i
    while (( gend < n )) && [[ "${MSEL_GROUPS[gend]}" == "$label" ]]; do
      gend=$(( gend + 1 ))
    done
    first=1
    while (( i < gend )); do
      len=$(( gend - i ))
      (( len > MSEL_COLS )) && len=$MSEL_COLS
      MSEL_ROW_START+=("$i")
      MSEL_ROW_LEN+=("$len")
      if (( first )); then
        MSEL_ROW_LABEL+=("$label")
        first=0
      else
        MSEL_ROW_LABEL+=("")
      fi
      for ((c=0; c<len; c++)); do
        MSEL_ROW_OF[i + c]=$r
        MSEL_COL_OF[i + c]=$c
      done
      i=$(( i + len ))
      r=$(( r + 1 ))
    done
  done
  return 0
}

# msel_cell <index> [last] — one grid cell, padded to MSEL_CELL unless it ends
# the row. Padding is computed from the ASCII name length only; the marker and
# glyph are multi-byte and are never measured with ${#}.
msel_cell() {
  local i=$1 last=${2:-0}
  local marker glyph name text pad maxname
  maxname=$(( MSEL_CELL - 3 ))
  name=${MSEL_NAMES[i]}
  (( ${#name} > maxname )) && name=${name:0:maxname}

  if (( i == MSEL_CURRENT )); then
    marker="${C_CYAN}›${C_RESET}"
    text="${C_CYAN}${C_BOLD}${name}${C_RESET}"
  else
    marker=" "
    text="$name"
  fi
  if [[ "${MSEL_SEL[i]}" == "1" ]]; then
    glyph="${C_GREEN}◉${C_RESET}"
  else
    glyph="${C_DIM}◌${C_RESET}"
  fi

  if (( last )); then
    printf '%s%s %s' "$marker" "$glyph" "$text"
  else
    pad=$(( MSEL_CELL - 3 - ${#name} ))
    (( pad < 1 )) && pad=1
    printf '%s%s %s%*s' "$marker" "$glyph" "$text" "$pad" ""
  fi
}

# msel_build — render the whole block into MSEL_LINES (header, hint, rail, grid).
msel_build() {
  MSEL_LINES=()
  local n=${#MSEL_KEYS[@]} term_w sel=0 i
  term_w=$(term_cols)
  for ((i=0; i<n; i++)); do
    if [[ "${MSEL_SEL[i]}" == "1" ]]; then sel=$(( sel + 1 )); fi
  done
  local skipped=$(( n - sel ))

  # " selected · " is 12 visible chars, " skipped" is 8 — counted, not measured,
  # because "·" is two bytes and ${#} would over-count it under the C locale.
  local counter_len=$(( ${#sel} + 12 + ${#skipped} + 8 ))
  local pad=$(( term_w - 3 - ${#MSEL_LABEL} - counter_len ))
  (( pad < 2 )) && pad=2
  MSEL_LINES+=("$(printf '%s◇%s  %s%s%s%*s%s%s selected · %s skipped%s' \
    "$C_ORANGE" "$C_RESET" "$C_BOLD" "$MSEL_LABEL" "$C_RESET" \
    "$pad" "" "$C_DIM" "$sel" "$skipped" "$C_RESET")")

  local hint="↑↓←→ move · space toggle · a all · n none · enter confirm"
  if (( 3 + $(vis_len "$hint") > term_w )); then
    hint="↑↓←→ · space · a/n · enter"
  fi
  MSEL_LINES+=("$(printf '%s│%s  %s%s%s' "$C_DIM" "$C_RESET" "$C_DIM" "$hint" "$C_RESET")")
  MSEL_LINES+=("$(printf '%s│%s' "$C_DIM" "$C_RESET")")

  local r nrows=${#MSEL_ROW_START[@]} line start len c idx last
  for ((r=0; r<nrows; r++)); do
    line=$(printf '%s│%s  %s%-*s%s' \
      "$C_DIM" "$C_RESET" "$C_DIM" "$MSEL_GUTTER" "${MSEL_ROW_LABEL[r]}" "$C_RESET")
    start=${MSEL_ROW_START[r]}
    len=${MSEL_ROW_LEN[r]}
    for ((c=0; c<len; c++)); do
      idx=$(( start + c ))
      last=0
      (( c == len - 1 )) && last=1
      line+=$(msel_cell "$idx" "$last")
    done
    MSEL_LINES+=("$line")
  done
  return 0
}

msel_print_all() {
  local line
  for line in "${MSEL_LINES[@]}"; do
    printf '%s\n' "$line"
  done
}

# msel_visible_rows — how many of the rendered lines are still on screen. This
# is the cursor-up distance; clamping it to the terminal height is what keeps
# the redraw correct when the block has scrolled.
msel_visible_rows() {
  local total=${#MSEL_LINES[@]} lines v
  lines=$(term_lines)
  v=$(( lines - 1 ))
  (( v > total )) && v=$total
  (( v < 1 )) && v=1
  printf '%s' "$v"
}

msel_redraw() {
  local total=${#MSEL_LINES[@]} v i
  v=$(msel_visible_rows)
  printf '\033[%dA' "$v"
  for ((i = total - v; i < total; i++)); do
    printf '\033[2K%s\n' "${MSEL_LINES[i]}"
  done
}

msel_right() {
  local n=${#MSEL_KEYS[@]}
  MSEL_CURRENT=$(( (MSEL_CURRENT + 1) % n ))
}

msel_left() {
  local n=${#MSEL_KEYS[@]}
  MSEL_CURRENT=$(( (MSEL_CURRENT - 1 + n) % n ))
}

# msel_vmove <±1> — same column on the adjacent grid row, clamped to that row's
# width so a short last row of a group still catches the cursor.
msel_vmove() {
  local d=$1 nrows=${#MSEL_ROW_START[@]} r c len
  r=$(( (MSEL_ROW_OF[MSEL_CURRENT] + d + nrows) % nrows ))
  c=${MSEL_COL_OF[MSEL_CURRENT]}
  len=${MSEL_ROW_LEN[r]}
  if (( c >= len )); then c=$(( len - 1 )); fi
  MSEL_CURRENT=$(( MSEL_ROW_START[r] + c ))
}

msel_up()   { msel_vmove -1; }
msel_down() { msel_vmove 1; }

msel_toggle() {
  if [[ "${MSEL_SEL[MSEL_CURRENT]}" == "1" ]]; then
    MSEL_SEL[MSEL_CURRENT]=0
  else
    MSEL_SEL[MSEL_CURRENT]=1
  fi
}

msel_select_all() {
  local i
  for ((i=0; i<${#MSEL_KEYS[@]}; i++)); do MSEL_SEL[i]=1; done
}

msel_select_none() {
  local i
  for ((i=0; i<${#MSEL_KEYS[@]}; i++)); do MSEL_SEL[i]=0; done
}

msel_collect() {
  PROMPT_MSEL_RESULT=()
  local i
  for ((i=0; i<${#MSEL_KEYS[@]}; i++)); do
    if [[ "${MSEL_SEL[i]}" == "1" ]]; then PROMPT_MSEL_RESULT+=("${MSEL_KEYS[i]}"); fi
  done
  return 0
}

# msel_collapse — clear the block back to its title line and replace it with one
# bounded summary line (never an unbounded ` · `-joined list).
msel_collapse() {
  local total=${#MSEL_LINES[@]} term_h v term_w
  term_h=$(term_lines)
  v=$(( total - 1 ))
  (( v > term_h - 2 )) && v=$(( term_h - 2 ))
  (( v < 0 )) && v=0
  (( v > 0 )) && printf '\033[%dA' "$v"
  printf '\033[J'

  msel_collect
  term_w=$(term_cols)
  if (( ${#PROMPT_MSEL_RESULT[@]} == 0 )); then
    printf '%s│%s  %s(none selected — baseline only)%s\n' "$C_DIM" "$C_RESET" "$C_DIM" "$C_RESET"
  else
    printf '%s│%s  %s%s%s\n' "$C_DIM" "$C_RESET" "$C_DIM" \
      "$(selection_summary "$(( term_w - 3 ))" "${MSEL_KEYS[*]}" "${PROMPT_MSEL_RESULT[*]}")" \
      "$C_RESET"
  fi
}

prompt_multiselect() {
  msel_parse "$@"
  msel_layout
  msel_build

  printf '\n'
  msel_print_all

  local k rest
  while :; do
    IFS= read -rsn1 k < /dev/tty || break
    case "$k" in
      $'\033')
        IFS= read -rsn2 -t 0.05 rest < /dev/tty || rest=""
        case "$rest" in
          '[A') msel_up ;;
          '[B') msel_down ;;
          '[C') msel_right ;;
          '[D') msel_left ;;
        esac
        ;;
      ' ') msel_toggle ;;
      '') break ;;
      'k') msel_up ;;
      'j') msel_down ;;
      'h') msel_left ;;
      'l') msel_right ;;
      'a') msel_select_all ;;
      'n') msel_select_none ;;
    esac
    msel_build
    msel_redraw
  done

  msel_collapse
}

# ════════════════════════════════════════════════════════════════════════════
# Component registry
# ════════════════════════════════════════════════════════════════════════════

# The six component groups, in display and registration order. Component blocks
# below are laid out group by group, so registration order matches this list.
declare -a COMPONENT_GROUPS=(core languages packaging agents cloud infra)

declare -a COMPONENTS=()
declare -A COMPONENT_NAME=()
declare -A COMPONENT_DESC=()
declare -A COMPONENT_DEFAULT=()
declare -A COMPONENT_SCOPE=()   # "system" or "user"
declare -A COMPONENT_GROUP=()   # one of COMPONENT_GROUPS
declare -A COMPONENT_INSTALL=()
declare -A COMPONENT_CHECK=()
declare -A COMPONENT_SIGNIN=()  # optional: short hint shown in do_check footer
declare -A COMPONENT_DEPS=([python]=uv [bun]=node [pnpm]=node [claude]=node
  [opencode]=node [codex]=node [gemini]=node [pi]=node [vercel]=node [neon]=node)

# Topological order, with registry order used to break ties. The selected set
# and dependency state are local to each resolution (including recursive calls).
resolve_components() {
  local -A visiting=() resolved=()
  local key
  for key in "$@"; do resolve_component "$key" || return; done
}

resolve_component() {
  local key=$1 dependency
  [[ "$key" =~ ^[a-z_][a-z0-9_]*$ ]] || return 1
  [[ -n ${COMPONENT_INSTALL[$key]:-} && ( ${COMPONENT_SCOPE[$key]:-} == system || ${COMPONENT_SCOPE[$key]:-} == user ) ]] || { printf 'Unknown component: %s\n' "$key" >&2; return 1; }
  [[ ${resolved[$key]:-0} == 1 ]] && return 0
  [[ ${visiting[$key]:-0} == 0 ]] || { printf 'Dependency cycle: %s\n' "$key" >&2; return 1; }
  visiting[$key]=1
  for dependency in ${COMPONENT_DEPS[$key]:-}; do resolve_component "$dependency" || return; done
  visiting[$key]=0
  resolved[$key]=1
  printf '%s\n' "$key"
}

# register <key> <name> <desc> <default 0|1> <scope system|user> <group> <install_fn> <check_fn> [signin_hint]
# group is required and must be one of COMPONENT_GROUPS.
# signin_hint is an optional one-line string shown under "Sign in:" in the do_check footer.
# Leave empty for components that need no post-install authentication.
register() {
  if (( $# < 8 )); then
    die "register ${1:-<key>}: expected at least 8 arguments (key name desc default scope group install_fn check_fn), got $#"
  fi
  local key=$1 name=$2 desc=$3 default=$4 scope=$5 group=$6 install_fn=$7 check_fn=$8
  local signin_hint=${9:-}
  COMPONENTS+=("$key")
  COMPONENT_NAME[$key]=$name
  COMPONENT_DESC[$key]=$desc
  COMPONENT_DEFAULT[$key]=$default
  COMPONENT_SCOPE[$key]=$scope
  COMPONENT_GROUP[$key]=$group
  COMPONENT_INSTALL[$key]=$install_fn
  COMPONENT_CHECK[$key]=$check_fn
  COMPONENT_SIGNIN[$key]=$signin_hint
}

# ── registry-derived labels and summaries ───────────────────────────────────
# Everything the wizard says about "how many tools" is computed here. The old
# hardcoded enumeration ("Docker · gh · Node LTS · Bun · Claude Code") named
# five of twelve and was wrong the moment a component was added.

# applicable_components — every registered key that applies to this run, in
# registration order, space separated.
applicable_components() {
  local key out=""
  for key in "${COMPONENTS[@]}"; do
    component_is_applicable "$key" || continue
    out+="${out:+ }$key"
  done
  printf '%s' "$out"
}

# full_install_keys — what "Full install" installs: every applicable default.
full_install_keys() {
  local key out=""
  for key in "${COMPONENTS[@]}"; do
    component_is_applicable "$key" || continue
    [[ "${COMPONENT_DEFAULT[$key]}" == "1" ]] || continue
    out+="${out:+ }$key"
  done
  printf '%s' "$out"
}

# component_group_counts <key>... — "core 4 · languages 5 · …" in
# COMPONENT_GROUPS order, skipping groups with nothing in them.
component_group_counts() {
  local g k c out=""
  for g in "${COMPONENT_GROUPS[@]}"; do
    c=0
    for k in "$@"; do
      if [[ "${COMPONENT_GROUP[$k]:-}" == "$g" ]]; then c=$(( c + 1 )); fi
    done
    (( c == 0 )) && continue
    out+="${out:+ · }$g $c"
  done
  printf '%s' "$out"
}

# full_install_option — the "Full install" radio option string, counts and all.
full_install_option() {
  local -a keys=()
  read -r -a keys <<< "$(full_install_keys)"
  printf 'Full install|everything — %d tools|%s' \
    "${#keys[@]}" "$(component_group_counts "${keys[@]}")"
}

# selection_summary <budget> "<all keys>" "<selected keys>"
# One line, never wider than <budget> visible characters. A full selection
# collapses to group counts; a partial one names the shorter half (usually the
# skipped items) and truncates with "+N more" rather than running off the line
# — a wrapped remainder carries no rail prefix and breaks the left border.
selection_summary() {
  local budget=$1
  local -a all=() chosen=()
  read -r -a all <<< "$2"
  read -r -a chosen <<< "$3"
  local total=${#all[@]} n=${#chosen[@]}

  if (( n == total )); then
    # The group counts are a list like any other, so they get the same
    # truncation the partial path gets: keep whole "<group> <n>" segments while
    # they fit, then "+K more", then — if even one segment overflows — the bare
    # count. "all N" is at most 8 characters, so something always fits.
    # "  ·  " is 5 visible chars and " · " is 3; counted, never measured,
    # because "·" is two bytes.
    local head="all $total"
    local -a segs=()
    local rest seg
    rest=$(component_group_counts "${all[@]}")
    while [[ -n "$rest" ]]; do
      if [[ "$rest" == *" · "* ]]; then
        seg="${rest%%" · "*}"
        rest="${rest#*" · "}"
      else
        seg="$rest"
        rest=""
      fi
      segs+=("$seg")
    done
    local room=$(( budget - ${#head} - 5 ))
    local tail="" tlen=0 tshown=0 tcount=${#segs[@]}
    local j tadd tremaining treserve
    for ((j=0; j<tcount; j++)); do
      seg="${segs[j]}"
      tadd=${#seg}
      (( tshown > 0 )) && tadd=$(( tadd + 3 ))
      tremaining=$(( tcount - j ))
      treserve=0
      if (( tremaining > 1 )); then
        # " · +K more"
        treserve=$(( 3 + 1 + ${#tremaining} + 5 ))
      fi
      if (( tlen + tadd + treserve > room )); then break; fi
      (( tshown > 0 )) && tail+=" · "
      tail+="$seg"
      tlen=$(( tlen + tadd ))
      tshown=$(( tshown + 1 ))
    done
    if (( tshown == 0 )); then
      printf '%s' "$head"
      return 0
    fi
    if (( tshown < tcount )); then
      tail+=" · +$(( tcount - tshown )) more"
    fi
    printf '%s  ·  %s' "$head" "$tail"
    return 0
  fi

  local -a skipped=() listed=()
  local k verb
  for k in "${all[@]}"; do
    if [[ " $3 " != *" $k "* ]]; then skipped+=("$k"); fi
  done
  if (( ${#skipped[@]} <= n )); then
    verb="skipped"
    listed=("${skipped[@]}")
  else
    verb="selected"
    listed=("${chosen[@]}")
  fi

  # "  ·  " is 5 visible chars, ": " is 2 — counted, never measured, because
  # "·" is two bytes.
  local pre="$n of $total"
  local room=$(( budget - ${#pre} - 5 - ${#verb} - 2 ))
  (( room < 10 )) && room=10

  local display_names="" len=0 shown=0 count=${#listed[@]}
  local i name add remaining reserve left

  # If the whole list fits, print it — no "+N more" that is longer than the
  # item it replaced.
  local all_len=0
  for ((i=0; i<count; i++)); do
    name="${COMPONENT_NAME[${listed[i]}]:-${listed[i]}}"
    all_len=$(( all_len + ${#name} ))
    (( i > 0 )) && all_len=$(( all_len + 3 ))
  done
  if (( all_len <= room )); then
    for ((i=0; i<count; i++)); do
      (( i > 0 )) && display_names+=" · "
      display_names+="${COMPONENT_NAME[${listed[i]}]:-${listed[i]}}"
    done
    printf '%s  ·  %s: %s' "$pre" "$verb" "$display_names"
    return 0
  fi

  for ((i=0; i<count; i++)); do
    name="${COMPONENT_NAME[${listed[i]}]:-${listed[i]}}"
    add=${#name}
    (( shown > 0 )) && add=$(( add + 3 ))
    remaining=$(( count - i ))
    reserve=0
    if (( remaining > 1 )); then
      # " · +N more"
      reserve=$(( 3 + 1 + ${#remaining} + 5 ))
    fi
    if (( len + add + reserve > room )); then break; fi
    (( shown > 0 )) && display_names+=" · "
    display_names+="$name"
    len=$(( len + add ))
    shown=$(( shown + 1 ))
  done
  left=$(( count - shown ))
  if (( left > 0 )); then
    (( shown > 0 )) && display_names+=" · "
    display_names+="+$left more"
  fi

  printf '%s  ·  %s: %s' "$pre" "$verb" "$display_names"
}

# ════════════════════════════════════════════════════════════════════════════
# Components — see CLAUDE.md for the contract
# Each component: install_<key>, check_<key>, register line.
# ════════════════════════════════════════════════════════════════════════════

# ══ core ══════════════════════════════════════════════════

# ─── passwordless sudo ─────────────────────────────────────
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

register sudo_nopasswd "Passwordless sudo" "sudo without password prompts" 1 system core \
  install_sudo_nopasswd check_sudo_nopasswd

# ─── tools ─────────────────────────────────────────────────
install_tools() {
  wait_for_apt
  apt install -y jq ripgrep fd-find htop tree

  # fd-find is packaged as 'fdfind' on Debian/Ubuntu to avoid collision with the
  # 'fd' package (a different tool). Expose the common name 'fd' via update-alternatives
  # so scripts and users can reach it by its standard name.
  update-alternatives --install /usr/local/bin/fd fd /usr/bin/fdfind 1
}

# Read the complete output before parsing: a successful producer must not
# become SIGPIPE merely because its version includes several lines.
version_value() {
  local output
  output=$("$@" 2>&1) || return 1
  [[ "$output" =~ ([0-9]+\.[0-9]+([.][0-9]+)?([-+][[:alnum:].-]+)?) ]] || return 1
  printf '%s\n' "${BASH_REMATCH[1]}"
}

report_version() {
  local label=$1 value
  shift
  if value=$(version_value "$@"); then ok "$label $value"
  else ko "$label unavailable or version command failed"; fi
}

check_tools() {
  local tool
  for tool in jq rg fd htop tree; do report_version "$tool" "$tool" --version; done
}

register tools "CLI tools" "jq, ripgrep, fd, htop, tree" 1 system core \
  install_tools check_tools

# ─── docker ────────────────────────────────────────────────
install_docker() {
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  local arch codename
  arch=$(dpkg --print-architecture)
  codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
  echo "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $codename stable" \
    > /etc/apt/sources.list.d/docker.list
  wait_for_apt
  apt update -y
  wait_for_apt
  apt install -y \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
  add_docker_group_if_needed
}

check_docker() {
  if systemctl is-active --quiet docker; then ok "docker daemon active"
  else ko "docker daemon not running"; fi
  report_version docker docker --version
  report_version compose docker compose version --short
  report_version buildx docker buildx version
  if [[ "$USERNAME" != root ]]; then
    if id -nG "$USERNAME" | tr ' ' '\n' | grep -qx docker; then ok "$USERNAME in docker group"
    else ko "$USERNAME not in docker group"; fi
  fi
}

register docker "Docker + Compose" "containers + compose plugin" 1 system core install_docker check_docker

# ─── gh ────────────────────────────────────────────────────
install_gh() {
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg status=none
  chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
  local arch
  arch=$(dpkg --print-architecture)
  echo "deb [arch=$arch signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list
  wait_for_apt
  apt update -y
  wait_for_apt
  apt install -y gh
}

check_gh() {
  report_version "gh" gh --version
}

register gh "GitHub CLI" "gh" 1 system core install_gh check_gh \
  "gh auth login            (paste the one-time code in your browser)"

# ══ languages ═════════════════════════════════════════════

# ─── node ──────────────────────────────────────────────────
install_node() {
  curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
  wait_for_apt
  apt install -y nodejs
}

check_node() {
  report_version "node" node --version
  report_version "npm" npm --version
}

register node "Node LTS" "current LTS via NodeSource" 1 system languages install_node check_node

# ─── python ────────────────────────────────────────────────
install_python() {
  install -d -m 0755 "$PYTHON_HOME"
  local py py_version environment
  UV_PYTHON_INSTALL_DIR="$PYTHON_HOME" uv --no-config python install 3
  py=$(UV_PYTHON_INSTALL_DIR="$PYTHON_HOME" uv --no-config python find --managed-python 3)
  "$py" -c 'import sys; assert sys.version_info.releaselevel == "final"'
  py_version=$("$py" -c 'import platform; print(platform.python_version())')
  environment="$PYTHON_HOME/venvs/$py_version"
  # uv-managed interpreters are externally managed. Seed pip in a separate
  # development venv instead of modifying the managed interpreter itself.
  if ! "$environment/bin/python" -m pip --version >/dev/null 2>&1; then
    uv --no-config venv --seed --allow-existing --python "$py" "$environment"
  fi
  "$environment/bin/python" -m pip --version
  chmod -R a+rX "$PYTHON_HOME"
  # Only expose python, never shadow Ubuntu's python3 (including via PATH).
  # A symlink outside the venv can resolve through uv's interpreter symlink
  # and lose pyvenv.cfg discovery. Exec its original path instead.
  printf '#!/bin/sh\nexec "%s/bin/python" "$@"\n' "$environment" > "${PYTHON_BIN}.new"
  chmod 0755 "${PYTHON_BIN}.new"
  mv -Tf "${PYTHON_BIN}.new" "$PYTHON_BIN"
}

check_python() {
  if ! "$PYTHON_BIN" -c 'import sys; assert sys.version_info.releaselevel == "final"' 2>/dev/null; then
    ko "python missing or not a stable release"
  else
    report_version python "$PYTHON_BIN" --version
  fi
  report_version pip "$PYTHON_BIN" -m pip --version
}

register python "Python + pip" "stable Python 3 via uv" 1 system languages install_python check_python

# ─── go ────────────────────────────────────────────────────
install_go() (
  set -euo pipefail
  local ver archive checksum tmp_dir previous
  ver=$(curl -fsSL "https://go.dev/VERSION?m=text" | sed -n '1p')
  [[ "$ver" =~ ^go[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || return 1
  archive="${ver}.linux-amd64.tar.gz"
  tmp_dir=$(mktemp -d /usr/local/.go-download.XXXXXX)
  trap 'rm -rf -- "$tmp_dir"' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  checksum=$(curl -fsSL 'https://go.dev/dl/?mode=json' | python3 -c 'import json,sys; print(next(f["sha256"] for r in json.load(sys.stdin) for f in r["files"] if f["filename"] == sys.argv[1]))' "$archive")
  [[ "$checksum" =~ ^[0-9a-f]{64}$ ]] || return 1
  curl -fsSL "https://go.dev/dl/$archive" -o "$tmp_dir/$archive"
  printf '%s  %s\n' "$checksum" "$tmp_dir/$archive" | sha256sum -c -
  tar -C "$tmp_dir" -xzf "$tmp_dir/$archive"
  "$tmp_dir/go/bin/go" version
  previous=/usr/local/go.previous
  [[ ! -e "$previous" ]] || { echo "Previous Go backup requires inspection" >&2; return 1; }
  if [[ -e /usr/local/go ]]; then mv /usr/local/go "$previous"; fi
  if ! mv "$tmp_dir/go" /usr/local/go; then
    [[ ! -e "$previous" ]] || mv "$previous" /usr/local/go
    return 1
  fi
  rm -rf "$previous"
  printf 'export PATH=$PATH:/usr/local/go/bin\n' > /etc/profile.d/go.sh
  chmod 644 /etc/profile.d/go.sh
)

check_go() {
  report_version "go" /usr/local/go/bin/go version
}

register go "Go" "latest Go via go.dev" 1 system languages install_go check_go

# ─── java ──────────────────────────────────────────────────
# Probe descending for the newest installable *LTS* openjdk-NN-jdk-headless,
# split out from install_java so the filter can be exercised without a
# privileged filesystem write. This borrows install_python's --dry-run
# probing idiom, but restricted to LTS majors: since Java 17 the LTS cadence
# is every four feature releases (two years), so 17/21/25/29/33/... are
# exactly the LTS majors, satisfying (n - 21) % 4 == 0. Without the filter,
# "newest installable" and "newest LTS" only coincide today by accident of
# Ubuntu's backport policy (noble ships only LTS JDKs: 17/21/25, not
# 22/23/24/26) — Ubuntu does package feature releases into interim distros,
# and a six-month feature release on a box meant to run unattended is the
# wrong default. default-jdk (21 on noble) is one LTS behind for the same
# reason: "default", "newest" and "newest LTS" are three different versions
# for Java, unlike go/python where they collapse into one.
probe_java_lts_jdk() {
  local n candidate
  for (( n = 40; n >= 17; n-- )); do
    (( (n - 21) % 4 == 0 )) || continue
    candidate=$(apt-cache policy "openjdk-${n}-jdk-headless" | awk '/Candidate:/ {print $2}')
    [[ -n "$candidate" && "$candidate" != '(none)' ]] || continue
    [[ ! "$candidate" =~ (ea|alpha|beta|rc) ]] || continue
    wait_for_apt
    apt install -y --dry-run "openjdk-${n}-jdk-headless" >/dev/null 2>&1 || continue
    printf 'openjdk-%s-jdk-headless\n' "$n"
    return 0
  done
  return 1
}

install_java() {
  local jdk n
  jdk=$(probe_java_lts_jdk) || { echo "no installable LTS JDK found" >&2; return 1; }
  n=${jdk#openjdk-}
  n=${n%-jdk-headless}
  wait_for_apt
  apt install -y "$jdk"

  # apt-installed OpenJDK lands at this well-known update-alternatives path;
  # deriving JAVA_HOME from it (rather than from `command -v javac`) keeps
  # the drop-in correct even though /usr/bin isn't re-resolved mid-process.
  local java_home
  java_home="/usr/lib/jvm/java-${n}-openjdk-$(dpkg --print-architecture)"
  printf 'export JAVA_HOME=%s\n' "$java_home" > /etc/profile.d/java.sh
  chmod 644 /etc/profile.d/java.sh
}

check_java() {
  local jv cv
  if jv=$(version_value java -version) && cv=$(version_value javac -version); then
    ok "java $jv (javac $cv)"
  else ko "java/javac unavailable or version command failed"; fi
}

register java "Java (JDK)" "newest installable LTS OpenJDK" 1 system languages install_java check_java

# ─── rust ──────────────────────────────────────────────────
install_rust() {
  # Bare `rustup` is interactive (prints a menu and waits); a prompt inside
  # step_run hangs the run silently since stdout is redirected to the log.
  # -y --no-modify-path plus pinned RUSTUP_HOME/CARGO_HOME is the
  # containerised-Rust recipe: system-wide install, no PATH edit, no shell rc
  # mutation — the profile.d drop-in below does that instead, so it works for
  # root and any created user alike.
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | RUSTUP_HOME="$RUSTUP_HOME_DIR" CARGO_HOME="$CARGO_HOME_DIR" \
      sh -s -- -y --no-modify-path --default-toolchain stable

  cat > /etc/profile.d/rust.sh <<PROFILE
export RUSTUP_HOME=$RUSTUP_HOME_DIR
export CARGO_HOME=\$HOME/.cargo
export PATH=\$PATH:$CARGO_HOME_DIR/bin
PROFILE
  chmod 644 /etc/profile.d/rust.sh
}

check_rust() {
  # $CARGO_HOME_DIR/bin isn't on this process's PATH until profile.d is
  # sourced by a fresh login shell, so check against the pinned install dir
  # directly — the same reason check_go uses an absolute path.
  if [ ! -x "$CARGO_HOME_DIR/bin/rustc" ] || [ ! -x "$CARGO_HOME_DIR/bin/cargo" ]; then
    ko "rust not installed"
    return
  fi
  # Those binaries are rustup *shims*: they resolve the default toolchain out
  # of RUSTUP_HOME, and with the variable unset they fail against ~/.rustup
  # even though the toolchain is installed. Exporting it is the difference
  # between a real version and the "?" that used to be reported as a pass.
  local rv cv
  rv=$(RUSTUP_HOME="$RUSTUP_HOME_DIR" CARGO_HOME="$CARGO_HOME_DIR" version_value "$CARGO_HOME_DIR/bin/rustc" --version) || rv=""
  cv=$(RUSTUP_HOME="$RUSTUP_HOME_DIR" CARGO_HOME="$CARGO_HOME_DIR" version_value "$CARGO_HOME_DIR/bin/cargo" --version) || cv=""
  # A shim that cannot name a version is a broken toolchain, not a pass.
  if [[ -z "$rv" || -z "$cv" ]]; then
    ko "rust installed but no default toolchain — run 'rustup default stable'"
    return
  fi
  ok "rust $rv (cargo $cv)"
}

register rust "Rust" "rustup toolchain (rustc, cargo)" 1 system languages install_rust check_rust

# ══ packaging ═════════════════════════════════════════════

# ─── bun ───────────────────────────────────────────────────
install_bun() {
  npm install --engine-strict -g bun
}

check_bun() {
  report_version "bun" bun --version
}

register bun "Bun" "JS runtime" 1 system packaging install_bun check_bun

# ─── pnpm ──────────────────────────────────────────────────
install_pnpm() {
  npm install --engine-strict -g pnpm
}

check_pnpm() {
  report_version "pnpm" pnpm --version
}

register pnpm "pnpm" "fast npm-compatible package manager" 1 system packaging install_pnpm check_pnpm

# ─── uv ────────────────────────────────────────────────────
install_uv() {
  # Upstream defaults to $HOME/.local/bin, not on PATH for a fresh root-only
  # box. UV_INSTALL_DIR pins it system-wide instead, mirroring
  # install_herdr's pinned-install-dir fix.
  curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh
}

check_uv() {
  report_version "uv" uv --version
}

register uv "uv" "fast Python package/venv manager" 1 system packaging install_uv check_uv

# ══ agents ════════════════════════════════════════════════

# ─── claude code ───────────────────────────────────────────
install_claude() {
  npm install --engine-strict -g @anthropic-ai/claude-code
}

check_claude() {
  report_version "claude" claude --version
}

register claude "Claude Code" "Anthropic's CLI" 1 system agents install_claude check_claude \
  "claude                   (first run opens the OAuth browser flow)"

# ─── opencode ──────────────────────────────────────────────
install_opencode() {
  npm install --engine-strict -g opencode-ai
}

check_opencode() {
  report_version "opencode" opencode --version
}

register opencode "opencode" "open-source AI coding agent" 1 system agents install_opencode check_opencode \
  "opencode auth login      (pick a provider and paste its API key)"

# ─── codex ─────────────────────────────────────────────────
install_codex() {
  npm install --engine-strict -g @openai/codex
}

check_codex() {
  report_version "codex" codex --version
}

register codex "Codex" "OpenAI's CLI coding agent" 1 system agents install_codex check_codex \
  "codex                    (first run opens the OAuth browser flow)"

# ─── gemini ────────────────────────────────────────────────
install_gemini() {
  npm install --engine-strict -g @google/gemini-cli
}

check_gemini() {
  report_version "gemini" gemini --version
}

register gemini "Gemini CLI" "Google's CLI coding agent" 1 system agents install_gemini check_gemini \
  "gemini                   (first run opens the OAuth browser flow)"

# ─── pi ────────────────────────────────────────────────────
install_pi() {
  # Upstream's documented shell installer (hosted on the vendor's own
  # install-script domain) prompts interactively to edit PATH; a prompt
  # inside step_run hangs the run silently, since stdout is redirected to
  # the log. Install the npm package instead — same binary, no prompt.
  npm install --engine-strict -g @earendil-works/pi-coding-agent
}

check_pi() {
  report_version "pi" pi --version
}

register pi "pi" "Earendil's CLI coding agent" 1 system agents install_pi check_pi \
  "pi login                 (pick a provider and paste its API key)"

# ─── hermes ────────────────────────────────────────────────
# The user-scope script is emitted by a function rather than inlined, so the
# suite can run it with a stubbed `curl` and assert where it ends up.
hermes_user_script() {
  cat <<'SCRIPT'
set -eo pipefail
# `sudo -u <user> -H bash` sets HOME but inherits the caller's working
# directory, and the caller is root in /root (mode 700). Anything the
# installer runs that touches "." then fails as the unprivileged user — uv
# probes for uv.toml and .venv and dies with EACCES before it starts. Leave
# that directory first; -H already points HOME at the right place.
cd "$HOME" || exit 1
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh \
  | bash -s -- --skip-setup
SCRIPT
}

install_hermes() (
  # Upstream installer shells out to `sudo apt-get install ffmpeg` as
  # $USERNAME, which would prompt. Drop a temporary NOPASSWD rule for the
  # duration of the install and remove it on the way out (success or fail).
  local sudoers="$SUDOERS_DIR/99-vps-boot-hermes"
  [[ ! -e "$sudoers" ]] || { echo "Existing Hermes sudoers file requires inspection" >&2; return 1; }
  trap 'rm -f -- "$sudoers"' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$USERNAME" > "$sudoers"
  chmod 440 "$sudoers"
  visudo -cf "$sudoers"
  # Upstream probes PATH with an interactive bash. With our redirected logs
  # and an SSH controlling terminal, its job control can suspend the install.
  # A separate session has no controlling terminal; --wait preserves failures.
  sudo -u "$USERNAME" -H setsid --fork --wait bash -c "$(hermes_user_script)" </dev/null
  rm -f "$sudoers"
  trap - EXIT HUP INT TERM
)

check_hermes() {
  report_version hermes sudo -u "$USERNAME" -H bash -lc 'cd "$HOME" || exit 1; hermes --version'
}

register hermes "Hermes" "NousResearch AI agent" 1 user agents install_hermes check_hermes \
  "hermes setup             (configure LLM provider and API keys)"

# ══ cloud ═════════════════════════════════════════════════

# ─── vercel ────────────────────────────────────────────────
install_vercel() {
  npm install --engine-strict -g vercel
}

check_vercel() {
  report_version "vercel" vercel --version
}

register vercel "Vercel CLI" "deploy and manage Vercel projects" 1 system cloud install_vercel check_vercel \
  "vercel login --no-browser (bare login waits on a browser callback and hangs headless)"

# ─── neon ──────────────────────────────────────────────────
install_neon() {
  npm install --engine-strict -g neonctl
}

check_neon() {
  report_version "neonctl" neonctl --version
}

register neon "Neon CLI" "manage Neon Postgres branches and projects" 1 system cloud install_neon check_neon

# ─── hostinger ─────────────────────────────────────────────
install_hostinger() (
  local ver arch asset base_url tmp_dir
  ver=$(curl -fsSL https://api.github.com/repos/hostinger/api-cli/releases/latest \
    | grep -oP '"tag_name":\s*"v\K[^"]+')

  case "$(dpkg --print-architecture)" in
    amd64) arch=amd64 ;;
    arm64) arch=arm64 ;;
    i386)  arch=386 ;;
    *) echo "unsupported architecture: $(dpkg --print-architecture)" >&2; return 1 ;;
  esac

  asset="hostinger-${ver}-linux-${arch}.tar.gz"
  base_url="https://github.com/hostinger/api-cli/releases/download/v${ver}"

  tmp_dir=$(mktemp -d)
  trap 'rm -rf -- "$tmp_dir"' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  curl -fsSL -o "$tmp_dir/$asset" "$base_url/$asset"
  curl -fsSL -o "$tmp_dir/checksums.sha256" "$base_url/hostinger-${ver}-checksums.sha256"

  # Verify the download against the release's published checksums before
  # installing anything. No manual pass/fail branching here: with pipefail
  # set, a missing checksum entry (empty grep output) or a mismatch both
  # make sha256sum exit non-zero, which set -euo pipefail turns into a
  # failed step — never an unverified binary reaching /usr/local/bin.
  (cd "$tmp_dir" && grep -F -- "  $asset" checksums.sha256 | sha256sum -c -)

  tar -C "$tmp_dir" -xzf "$tmp_dir/$asset" hostinger
  install -m 755 "$tmp_dir/hostinger" /usr/local/bin/hostinger
)

check_hostinger() {
  report_version "hostinger" hostinger version
}

register hostinger "Hostinger CLI" "manage your Hostinger account from the API" 1 system cloud install_hostinger check_hostinger \
  "edit ~/.hostinger.yaml   (api_token is account-wide — it can rebuild your VPS)"

# ══ infra ═════════════════════════════════════════════════

# ─── caddy ─────────────────────────────────────────────────
install_caddy() {
  # Official apt repo + keyring, same shape as install_docker/install_gh.
  # `gpg --dearmor` is required here (unlike gh's keyring): Caddy's gpg.key
  # endpoint serves an ASCII-armored key, and the debian.deb.txt source line
  # below references the dearmored binary keyring path by name.
  curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/gpg.key \
    | gpg --batch --yes --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  chmod go+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt \
    -o /etc/apt/sources.list.d/caddy-stable.list
  wait_for_apt
  apt update -y
  wait_for_apt
  apt install -y caddy
  ufw allow 80/tcp comment 'Caddy HTTP'
  ufw allow 443/tcp comment 'Caddy HTTPS'
}

check_caddy() {
  if systemctl is-active --quiet caddy; then
    report_version caddy caddy version
  else
    ko "caddy service not active"
  fi

  local ufw_out
  ufw_out=$(ufw status 2>/dev/null)
  if grep -qE '^80/tcp[[:space:]]+ALLOW' <<< "$ufw_out" \
     && grep -qE '^443/tcp[[:space:]]+ALLOW' <<< "$ufw_out"; then
    ok "UFW allows 80/tcp and 443/tcp"
  else
    note "UFW denies 80/443 — run 'ufw allow 80/tcp && ufw allow 443/tcp' to expose Caddy"
  fi
}

register caddy "Caddy" "web server / reverse proxy; opens 80/443 TCP" 1 system infra install_caddy check_caddy

# ─── herdr ─────────────────────────────────────────────────
install_herdr() {
  # Upstream defaults to $HOME/.local/bin, which is not on PATH for a fresh
  # root-only box. HERDR_INSTALL_DIR pins it system-wide instead, so the
  # binary works for root and any created user alike.
  curl -fsSL https://herdr.dev/install.sh | HERDR_INSTALL_DIR=/usr/local/bin sh
}

check_herdr() {
  report_version "herdr" herdr --version
}

register herdr "herdr" "agent-aware terminal multiplexer" 1 system infra install_herdr check_herdr

# ════════════════════════════════════════════════════════════════════════════
# Baseline (mandatory, ordered) — NOT registered, always run
# ════════════════════════════════════════════════════════════════════════════

install_apt_lock_timeout() {
  local config_dir candidate=""
  if [[ -e "$APT_LOCK_CONFIG" && ! -e "${APT_LOCK_CONFIG}.previous" ]]; then cp -p "$APT_LOCK_CONFIG" "${APT_LOCK_CONFIG}.previous" || return; fi
  config_dir=$(dirname "$APT_LOCK_CONFIG")
  if ! install -d -m 0755 "$config_dir"; then
    rm -f "$APT_LOCK_CONFIG"
    return 1
  fi
  if ! candidate=$(mktemp "$config_dir/.vps-boot-apt.XXXXXX"); then
    rm -f "$APT_LOCK_CONFIG"
    return 1
  fi
  if ! printf 'DPkg::Lock::Timeout "%s";\n' "$APT_LOCK_TIMEOUT" > "$candidate"; then
    rm -f "$candidate" "$APT_LOCK_CONFIG"
    return 1
  fi
  if ! chmod 0644 "$candidate"; then
    rm -f "$candidate" "$APT_LOCK_CONFIG"
    return 1
  fi
  if ! mv -f "$candidate" "$APT_LOCK_CONFIG"; then
    rm -f "$candidate" "$APT_LOCK_CONFIG"
    return 1
  fi
}

remove_apt_lock_timeout() {
  if [[ -f "${APT_LOCK_CONFIG}.previous" ]]; then mv -f "${APT_LOCK_CONFIG}.previous" "$APT_LOCK_CONFIG"
  else rm -f "$APT_LOCK_CONFIG"; fi
}

# wait_for_apt [budget] — blocks while another process holds the APT lists
# lock or the dpkg frontend lock, polling once a second up to `budget`
# seconds (default $APT_LOCK_TIMEOUT). DPkg::Lock::Timeout, written by
# install_apt_lock_timeout above, only bounds dpkg's own lock wait *inside*
# an apt/dpkg invocation — it does nothing for `apt update`, which takes
# /var/lib/apt/lists/lock before dpkg is ever invoked. That gap is what let
# issue #43 through: apt-daily(-upgrade).timer fires on a randomized delay
# after boot and can hold the lists lock right as an early component's
# `apt update` runs. Call this immediately before every `apt update` /
# `apt upgrade` / `apt install`.
wait_for_apt() {
  local budget=${1:-$APT_LOCK_TIMEOUT}
  command -v fuser >/dev/null 2>&1 || return 0

  local waited=0
  while fuser /var/lib/apt/lists/lock /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    if (( waited >= budget )); then
      warn "wait_for_apt: timed out after ${budget}s waiting for the apt/dpkg lock"
      return 1
    fi
    sleep 1
    waited=$(( waited + 1 ))
  done
}

# stop_apt_timers / restore_apt_timers — apt-daily.timer and
# apt-daily-upgrade.timer are enabled out of the box on a fresh Ubuntu image
# and fire on their own randomized schedule; that's the background apt-get
# run seen holding the lists lock in issue #43. wait_for_apt() above waits it
# out on each individual apt call, but the sturdier fix is to remove the race
# for the whole install: stop both timers — and kill any run already in
# flight by stopping their services too — before the first apt call, then
# start them again once the install is done, success or failure.
# bl_unattended still *enables* apt-daily-upgrade.timer (for every boot after
# this one); it deliberately does not pass `--now`, since that would start it
# again mid-install and reopen the exact race this closes. restore_apt_timers
# is what starts it back up.
stop_apt_timers() {
  local timer
  install -d -m 0700 "$JOURNAL_DIR"
  for timer in apt-daily.timer apt-daily-upgrade.timer; do
    if [[ ! -f "$JOURNAL_DIR/$timer" ]]; then
      local active
      active=$(systemctl is-active "$timer" 2>/dev/null || true)
      printf '%s\n' "$active" | atomic_state "$JOURNAL_DIR/$timer"
    fi
    systemctl stop "$timer" || return
  done
  # This also works on minimal images where fuser is not installed yet.
  local waited=0
  while systemctl is-active --quiet apt-daily.service || systemctl is-active --quiet apt-daily-upgrade.service; do
    (( waited < APT_LOCK_TIMEOUT )) || { warn "APT services still running after ${APT_LOCK_TIMEOUT}s"; return 1; }
    sleep 1
    waited=$((waited + 1))
  done
  # Let an in-flight package transaction finish; never kill dpkg's service.
  wait_for_apt
}

restore_apt_timers() {
  local timer failed=0
  for timer in apt-daily.timer apt-daily-upgrade.timer; do
    [[ -f "$JOURNAL_DIR/$timer" ]] || continue
    if [[ $(cat "$JOURNAL_DIR/$timer") == active ]] || systemctl is-enabled --quiet "$timer"; then
      if ! systemctl start "$timer"; then warn "Could not restore $timer"; failed=1; continue; fi
    fi
    rm -f "$JOURNAL_DIR/$timer"
  done
  return "$failed"
}

bl_update() {
  wait_for_apt
  apt update -y
  wait_for_apt
  apt upgrade -y
  wait_for_apt
  apt install -y \
    wget gnupg lsb-release ca-certificates \
    software-properties-common ufw fail2ban git unzip curl sudo \
    build-essential psmisc
}

# bl_unattended — installs unattended-upgrades and enables automatic security
# updates only. Automatic-Reboot stays false: rebooting an unattended host out
# from under whatever is running on it is a decision for the operator, not a
# default.
bl_unattended() {
  wait_for_apt
  apt install -y unattended-upgrades

  local config_dir candidate
  config_dir=$(dirname "$UNATTENDED_UPGRADES_CONFIG")
  install -d -m 0755 "$config_dir"
  candidate=$(mktemp "$config_dir/.vps-boot-unattended.XXXXXX")
  if ! cat > "$candidate" <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
#clear Unattended-Upgrade::Allowed-Origins;
#clear Unattended-Upgrade::Origins-Pattern;
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
EOF
  then
    rm -f "$candidate"
    return 1
  fi
  if ! chmod 0644 "$candidate"; then
    rm -f "$candidate"
    return 1
  fi
  if ! mv -f "$candidate" "$UNATTENDED_UPGRADES_CONFIG"; then
    rm -f "$candidate"
    return 1
  fi

  # Deliberately no `--now`: starting the timer immediately would restart the
  # apt-daily-upgrade race stop_apt_timers just closed, mid-install.
  # restore_apt_timers (cmd_install) starts it once the run is done.
  systemctl enable apt-daily-upgrade.timer
}

bl_user() {
  # non-interactive: useradd + chpasswd. password is in $USER_PASSWORD env.
  if ! id "$USERNAME" >/dev/null 2>&1; then useradd -m -s /bin/bash -c "" "$USERNAME"; fi
  [[ -n ${USER_PASSWORD:-} ]] || { echo "Password required to complete user setup" >&2; return 1; }
  echo "$USERNAME:$USER_PASSWORD" | chpasswd
  usermod -aG sudo "$USERNAME"
}

bl_ufw() {
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow "$SSH_PORT"/tcp comment 'SSH'
  ufw --force enable
}

ssh_listener() {
  ss -tlnpH 2>/dev/null | awk -v port="$1" '$4 ~ (":" port "$") && /"sshd"/ {found=1} END {exit !found}'
}

configure_network() (
  set -euo pipefail
  local backup="$JOURNAL_DIR/network-backup" previous_ports port
  # Retain recovery material across interruption. Opening the new port before
  # changing sshd also leaves the existing connection path available.
  if [[ ! -d "$backup" ]]; then
    install -d -m 0700 "$backup"
    cp -a /etc/ufw "$backup/ufw"
    ufw status > "$backup/ufw-status"
    if [[ -d /etc/systemd/system/ssh.socket.d ]]; then cp -a /etc/systemd/system/ssh.socket.d "$backup/socket-dropins"; fi
    cp -a "$SSHD_CONFIG" "$backup/sshd_config"
    if [[ -f "$SSHD_DROPIN" ]]; then cp -a "$SSHD_DROPIN" "$backup/dropin"; fi
    systemctl is-enabled ssh.socket > "$backup/socket" 2>/dev/null || true
    sshd -T | awk '$1 == "port" {print $2}' > "$backup/ports"
    touch "$backup/ready"
  fi
  [[ -f "$backup/ready" ]] || { echo "Incomplete network backup requires inspection" >&2; return 1; }
  rollback_network() {
    local rc=$?
    if (( rc != 0 )); then
      set +e
      cp -a "$backup/ufw/." /etc/ufw/
      cp -a "$backup/sshd_config" "$SSHD_CONFIG"
      if [[ -f "$backup/dropin" ]]; then cp -a "$backup/dropin" "$SSHD_DROPIN"
      else rm -f "$SSHD_DROPIN"; fi
      if [[ $(cat "$backup/socket") != masked ]]; then systemctl unmask ssh.socket; fi
      if [[ -d "$backup/socket-dropins" ]]; then
        mkdir -p /etc/systemd/system/ssh.socket.d
        cp -a "$backup/socket-dropins/." /etc/systemd/system/ssh.socket.d/
      fi
      systemctl daemon-reload
      if sshd -t; then systemctl restart ssh.service; fi
      if [[ $(cat "$backup/socket") == enabled ]]; then systemctl enable --now ssh.socket; fi
      if grep -q "Status: active" "$backup/ufw-status"; then ufw --force enable
      else ufw --force disable; fi
      warn "Network change failed; previous configuration restored from $backup. Verify console connectivity."
    fi
    exit "$rc"
  }
  trap rollback_network EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  previous_ports=$(cat "$backup/ports")
  for port in $previous_ports; do ufw allow "$port/tcp" comment 'SSH transition'; done
  bl_ufw
  # A resume must never turn password authentication back on.
  if ! ssh_listener "$SSH_PORT" || [[ ! -f "$STATE_CONFIG" ]]; then bl_ssh_harden; fi
  ssh_listener "$SSH_PORT"
  for port in $previous_ports; do
    if [[ "$port" != "$SSH_PORT" ]]; then ufw --force delete allow "$port/tcp"; fi
  done
  write_state_config
  rm -rf -- "$backup"
  trap - EXIT HUP INT TERM
)

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

lockdown_ssh() {
  local permit_root=no
  [[ "$USERNAME" == "root" ]] && permit_root=prohibit-password
  apply_sshd_policy "$permit_root" no no 1
}

sshd_effective_config() {
  local context_user=${1:-$USERNAME}
  sshd -T -f "$SSHD_CONFIG" \
    -C "user=$context_user,host=localhost,addr=127.0.0.1" 2>/dev/null
}

sshd_effective_value() {
  local key=${1,,} context_user=${2:-$USERNAME}
  sshd_effective_config "$context_user" \
    | awk -v wanted="$key" '$1 == wanted { print $2; exit }'
}

sshd_root_is_key_only() {
  [[ "$1" == "prohibit-password" || "$1" == "without-password" ]]
}

sshd_root_matches_policy() {
  local actual=$1 expected=$2
  case "$expected" in
    prohibit-password|without-password)
      sshd_root_is_key_only "$actual"
      ;;
    *)
      [[ "$actual" == "$expected" ]]
      ;;
  esac
}

# hardening_is_applied — true when this host is in the locked-down state
# lockdown_ssh produces: password methods off, and root either key-only (root
# install) or refused outright (created user).
#
# Deliberately derived from `sshd -T` rather than from a marker file: the drop-in
# can be hand-edited during a lockout recovery, and a marker that disagrees with
# the running daemon is worse than no marker at all.
hardening_is_applied() {
  local password_auth root_login
  password_auth=$(sshd_effective_value passwordauthentication || true)
  [[ "$password_auth" == "no" && $(sshd_effective_value kbdinteractiveauthentication) == no ]] || return 1
  root_login=$(sshd_effective_value permitrootlogin || true)
  if [[ "$USERNAME" == "root" ]]; then
    sshd_root_is_key_only "$root_login"
  else
    [[ "$root_login" == "no" ]]
  fi
}

validate_sshd_listeners() {
  local effective=$1 entry address port
  local found_listener=0 found_remote=0

  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    found_listener=1
    if [[ "$entry" =~ ^\[([^]]+)\]:([0-9]+)$ ]]; then
      address=${BASH_REMATCH[1]}
      port=${BASH_REMATCH[2]}
    elif [[ "$entry" =~ ^([^:]+):([0-9]+)$ ]]; then
      address=${BASH_REMATCH[1]}
      port=${BASH_REMATCH[2]}
    else
      printf 'ERROR: cannot parse effective SSH ListenAddress: %s\n' "$entry" >&2
      return 1
    fi

    if [[ "$port" != "$SSH_PORT" ]]; then
      printf 'ERROR: effective SSH ListenAddress uses unexpected port: %s\n' "$entry" >&2
      return 1
    fi

    case "${address,,}" in
      127.*|::1|0:0:0:0:0:0:0:1|::ffff:127.*|0:0:0:0:0:ffff:127.*)
        ;;
      *)
        found_remote=1
        ;;
    esac
  done < <(awk '$1 == "listenaddress" { print $2 }' <<< "$effective")

  if (( ! found_listener )); then
    printf 'ERROR: effective SSH configuration has no ListenAddress\n' >&2
    return 1
  fi
  if (( ! found_remote )); then
    printf 'ERROR: effective SSH listeners are loopback-only on port %s\n' "$SSH_PORT" >&2
    return 1
  fi
}

validate_sshd_policy() {
  local expected_root=$1 expected_password=$2 expected_kbd=$3
  local effective root_effective actual_root actual_password actual_kbd
  local -a ports=()

  # sshd -t refuses to run without this dir. Normally created by
  # systemd-tmpfiles at boot once ssh.service has started at least once;
  # a host still on socket-activated ssh (ssh.socket) may never have had
  # ssh.service start, so it can be missing the first time we get here.
  install -d -m 0755 /run/sshd

  sshd -t -f "$SSHD_CONFIG" || return 1
  effective=$(sshd_effective_config "$USERNAME") || return 1
  if [[ "$USERNAME" == "root" ]]; then
    root_effective=$effective
  else
    root_effective=$(sshd_effective_config root) || return 1
  fi
  mapfile -t ports < <(awk '$1 == "port" { print $2 }' <<< "$effective")
  if (( ${#ports[@]} != 1 )) || [[ "${ports[0]:-}" != "$SSH_PORT" ]]; then
    printf 'ERROR: effective SSH ports must be exactly: %s\n' "$SSH_PORT" >&2
    return 1
  fi
  validate_sshd_listeners "$effective" || return 1

  actual_root=$(awk '$1 == "permitrootlogin" { print $2; exit }' <<< "$root_effective")
  actual_password=$(awk '$1 == "passwordauthentication" { print $2; exit }' <<< "$effective")
  actual_kbd=$(awk '$1 == "kbdinteractiveauthentication" { print $2; exit }' <<< "$effective")

  if ! sshd_root_matches_policy "$actual_root" "$expected_root"; then
    printf 'ERROR: effective PermitRootLogin is %s, expected %s\n' \
      "${actual_root:-unset}" "$expected_root" >&2
    return 1
  fi
  if [[ "$actual_password" != "$expected_password" ]]; then
    printf 'ERROR: effective PasswordAuthentication is %s, expected %s\n' \
      "${actual_password:-unset}" "$expected_password" >&2
    return 1
  fi
  if [[ "$actual_kbd" != "$expected_kbd" ]]; then
    printf 'ERROR: effective KbdInteractiveAuthentication is %s, expected %s\n' \
      "${actual_kbd:-unset}" "$expected_kbd" >&2
    return 1
  fi
}

restore_sshd_dropin() {
  local backup=$1 had_previous=$2
  if (( had_previous )); then
    mv -f "$backup" "$SSHD_DROPIN"
  else
    rm -f "$SSHD_DROPIN" "$backup"
  fi
}

apply_sshd_policy() {
  local permit_root=$1 password_auth=$2 kbd_auth=$3 reload_service=${4:-0}
  local config_dir backup="" had_previous=0
  config_dir=$(dirname "$SSHD_DROPIN")
  install -d -m 0755 "$config_dir"

  if [[ -e "$SSHD_DROPIN" ]]; then
    had_previous=1
    backup=$(mktemp "$config_dir/.vps-boot-sshd-backup.XXXXXX")
    if ! cp -p "$SSHD_DROPIN" "$backup"; then
      rm -f "$backup"
      return 1
    fi
  fi

  if ! write_sshd_dropin "$permit_root" "$password_auth" "$kbd_auth"; then
    rm -f "$backup"
    return 1
  fi
  if ! validate_sshd_policy "$permit_root" "$password_auth" "$kbd_auth"; then
    restore_sshd_dropin "$backup" "$had_previous" || return 1
    return 1
  fi

  if (( reload_service )) && ! systemctl reload ssh.service; then
    restore_sshd_dropin "$backup" "$had_previous" || return 1
    if sshd -t -f "$SSHD_CONFIG"; then
      systemctl reload ssh.service || true
    fi
    return 1
  fi

  rm -f "$backup"
}

bl_ssh_harden() {
  local permit_root=no
  cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.$(date +%s)"

  if [[ "$USERNAME" == "root" ]]; then
    permit_root=yes
  fi
  if [[ -f "$SSHD_DROPIN" ]] && hardening_is_applied; then
    apply_sshd_policy "$(sshd_effective_value permitrootlogin)" no no 0
  else
    apply_sshd_policy "$permit_root" yes yes 0
  fi

  # Make ssh.service the canonical listener. Mask ssh.socket so it can't
  # auto-bind :22 on reboot or after an openssh-server upgrade.
  systemctl disable --now ssh.socket 2>/dev/null || true
  systemctl mask        ssh.socket 2>/dev/null || true
  rm -f /etc/systemd/system/ssh.socket.d/listen.conf
  rmdir /etc/systemd/system/ssh.socket.d 2>/dev/null || true

  systemctl unmask ssh.service 2>/dev/null || true
  systemctl enable ssh.service 2>/dev/null || true
  systemctl daemon-reload

  # KillMode=process leaves orphan sshd listeners on the old port; pkill them.
  # User sessions are forked children, not [listener] masters, so they survive.
  systemctl stop ssh.service 2>/dev/null || true
  pkill -TERM -f 'sshd:.*-D \[listener\]' 2>/dev/null || true
  sleep 1
  pkill -KILL -f 'sshd:.*-D \[listener\]' 2>/dev/null || true
  systemctl start ssh.service

  # Confirm the kernel actually bound the new port. systemctl restart can
  # return success without the listener coming up cleanly in edge cases.
  local i
  for ((i=0; i<5; i++)); do
    if ssh_listener "$SSH_PORT"; then
      return 0
    fi
    sleep 1
  done
  echo "ERROR: ssh.service did not bind to port $SSH_PORT" >&2
  ss -tlnH 2>&1 || true
  systemctl status ssh.service --no-pager -l 2>&1 || true
  journalctl -u ssh.service --no-pager -n 30 2>&1 || true
  return 1
}

bl_fail2ban() {
  cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port    = $SSH_PORT
backend = systemd
EOF
  systemctl enable --now fail2ban
}

# ════════════════════════════════════════════════════════════════════════════
# State
# ════════════════════════════════════════════════════════════════════════════

supported_platform() {
  [[ $1 == ubuntu && $2 == 26.04 && $3 == amd64 ]]
}

preflight() {
  [[ $EUID -eq 0 ]] || die "Must run as root."
  local ID VERSION_ID
  . /etc/os-release
  supported_platform "$ID" "$VERSION_ID" "$(dpkg --print-architecture)" \
    || die "Supported platform: Ubuntu 26.04 amd64."
  [[ -d /run/systemd/system ]] || die "systemd must be running."
  local tool
  for tool in flock setsid curl ss sshd ssh-keygen apt dpkg systemctl mktemp install; do
    command -v "$tool" >/dev/null || die "Missing prerequisite: $tool"
  done
}

acquire_install_lock() {
  install -d -m 0755 "$STATE_DIR"
  exec {INSTALL_LOCK_FD}>"$STATE_DIR/lock"
  flock -n "$INSTALL_LOCK_FD" || die "Another vps-boot operation is running."
}

atomic_state() {
  local target=$1 candidate
  candidate=$(mktemp "${target}.XXXXXX") || return
  if ! cat > "$candidate" || ! chmod 0600 "$candidate" || ! mv -f "$candidate" "$target"; then
    rm -f "$candidate"
    return 1
  fi
}

record_step() {
  printf '%s\n%s\n' "$2" "${3:-}" | atomic_state "$JOURNAL_DIR/$1"
}

step_status() {
  local value=""
  [[ ! -f "$JOURNAL_DIR/$1" ]] || IFS= read -r value < "$JOURNAL_DIR/$1" || true
  printf '%s' "$value"
}

initialize_journal() {
  install -d -m 0700 "$JOURNAL_DIR"
  printf '%s\n' "$USERNAME" "$SSH_PORT" "$CREATE_USER" "$VPS_BOOT_VERSION" | atomic_state "$JOURNAL_DIR/intent"
  if (( ${#enabled[@]} )); then printf '%s\n' "${enabled[@]}" | atomic_state "$STATE_FILE"
  else atomic_state "$STATE_FILE" < /dev/null; fi
  local key
  for key in update unattended user network fail2ban "${enabled[@]}"; do record_step "$key" pending; done
  printf '1\n' | atomic_state "$JOURNAL_DIR/schema"
}

probe_baseline() {
  case "$1" in
    update) [[ -z $(dpkg --audit) ]] && dpkg-query -W -f='${Status}' build-essential | grep -q 'install ok installed' ;;
    unattended) grep -q '^APT::Periodic::Unattended-Upgrade "1";' "$UNATTENDED_UPGRADES_CONFIG" ;;
    user) id "$USERNAME" >/dev/null && id -nG "$USERNAME" | tr ' ' '\n' | grep -qx sudo ;;
    network) validate_sshd_policy "$(sshd_effective_value permitrootlogin)" "$(sshd_effective_value passwordauthentication)" "$(sshd_effective_value kbdinteractiveauthentication)" && ssh_listener "$SSH_PORT" && ufw status | grep -qE "^${SSH_PORT}/tcp[[:space:]]+ALLOW" ;;
    fail2ban) systemctl is-active --quiet fail2ban && fail2ban-client status sshd >/dev/null ;;
  esac
}

probe_step() (
  local key=$1
  if [[ -n ${COMPONENT_CHECK[$key]:-} ]]; then
    PASS=0; FAIL=0; WARN=0
    "${COMPONENT_CHECK[$key]}"
    (( FAIL == 0 ))
  else probe_baseline "$key"; fi
)

journal_step() {
  local key=$1 label=$2 result rc had_errexit=0
  shift 2
  if [[ $(step_status "$key") == succeeded ]] && result=$(probe_step "$key" 2>&1); then
    record_step "$key" succeeded "$result"
    body "$label — already verified"
    return 0
  fi
  record_step "$key" running
  [[ $- == *e* ]] && had_errexit=1
  set +e
  step_run "$label" "$@"
  rc=$?
  (( had_errexit )) && set -e
  if (( rc != 0 )); then record_step "$key" failed; return "$rc"; fi
  if result=$(probe_step "$key" 2>&1); then
    record_step "$key" succeeded "$result"
  else
    record_step "$key" failed "$result"
    warn "$label installed but verification failed: $result"
    return 1
  fi
}

cmd_resume() {
  [[ -f "$JOURNAL_DIR/schema" && $(cat "$JOURNAL_DIR/schema") == 1 ]] \
    || die "No resumable installation. Legacy state supports check/harden only."
  local -a intent=() enabled=()
  mapfile -t intent < "$JOURNAL_DIR/intent"
  (( ${#intent[@]} == 4 )) || die "Invalid install intent."
  USERNAME=${intent[0]}; SSH_PORT=${intent[1]}; CREATE_USER=${intent[2]}
  valid_username "$USERNAME" && valid_install_port "$SSH_PORT" || die "Invalid recorded account or port."
  [[ $CREATE_USER == 0 || $CREATE_USER == 1 ]] || die "Invalid user mode."
  [[ ( $USERNAME == root && $CREATE_USER == 0 ) || ( $USERNAME != root && $CREATE_USER == 1 ) ]] || die "Invalid user mode."
  mapfile -t enabled < "$STATE_FILE"
  local resolved
  resolved=$(resolve_components "${enabled[@]}") || die "Invalid component selection."
  enabled=(); [[ -z "$resolved" ]] || mapfile -t enabled <<< "$resolved"
  selection_allows_port "$SSH_PORT" "${enabled[@]}" || die "Recorded SSH port conflicts with selected components."
  USER_PASSWORD=""
  if (( CREATE_USER )) && [[ $(step_status user) != succeeded ]]; then
    prompt_password "Password for $USERNAME" USER_PASSWORD
  fi
  banner
  [[ ! -L "$LOG_FILE" ]] || die "Refusing a symlink log file."
  ( umask 077; touch "$LOG_FILE" )
  run_install
}

# write_state_config — record the account and port this host was set up with,
# so `harden` needs no arguments. cmd_install calls it as soon as the port is
# real (right after bl_ssh_harden) rather than at the end of the run: the
# enrollment prompt that follows waits on a human and can be killed by a
# dropped connection, and `harden` still has to resolve its target afterwards.
write_state_config() {
  local candidate
  install -d -m 0755 "$STATE_DIR"
  candidate=$(mktemp "$STATE_DIR/.vps-boot-config.XXXXXX")
  if ! cat > "$candidate" <<EOF
# Managed by vps-boot
USERNAME=$USERNAME
SSH_PORT=$SSH_PORT
EOF
  then
    rm -f "$candidate"
    return 1
  fi
  if ! chmod 0644 "$candidate"; then
    rm -f "$candidate"
    return 1
  fi
  if ! mv -f "$candidate" "$STATE_CONFIG"; then
    rm -f "$candidate"
    return 1
  fi
}

# read_state_config — load what write_state_config recorded into
# STATE_USERNAME / STATE_SSH_PORT. Both stay empty when there is no state file:
# a legacy install, or a host set up by hand.
read_state_config() {
  STATE_USERNAME=""
  STATE_SSH_PORT=""
  [[ -r "$STATE_CONFIG" ]] || return 0
  local key value
  while IFS='=' read -r key value; do
    case "$key" in
      USERNAME) STATE_USERNAME=$value ;;
      SSH_PORT) STATE_SSH_PORT=$value ;;
    esac
  done < "$STATE_CONFIG"
}

# ════════════════════════════════════════════════════════════════════════════
# SSH key enrollment
# ════════════════════════════════════════════════════════════════════════════

# harden_command — the exact command to re-run hardening on this host. $0 is
# "bash" under `curl | sudo bash`, where there is no script on disk, so fall
# back to the documented remote invocation instead of an unrunnable path.
harden_command() {
  if [[ -f "$0" ]]; then
    printf 'sudo %s harden %s' "$0" "$USERNAME"
  else
    printf 'curl -fsSL %s | sudo bash -s harden %s' "$REMOTE_URL" "$USERNAME"
  fi
}

# enroll_ssh_key ["section title"] — the shared enrollment + lockdown body,
# reached inline from cmd_install and standalone from cmd_harden.
enroll_ssh_key() {
  local title=${1:-"Almost done — enroll your SSH key"}
  local user_home auth_keys vps_ip
  user_home=$(getent passwd "$USERNAME" | cut -d: -f6)
  auth_keys="$user_home/.ssh/authorized_keys"
  vps_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  [[ -z "$vps_ip" ]] && vps_ip="<vps-ip>"

  section "$title"
  body ""
  if hardening_is_applied; then
    body "${C_DIM}This host is already locked down — password auth is off.${C_RESET}"
    body ""
  fi
  body "${C_BOLD}Linux / macOS:${C_RESET}"
  body "  ${C_CYAN}ssh-copy-id -p $SSH_PORT $USERNAME@$vps_ip${C_RESET}"
  body ""
  body "${C_BOLD}Windows (PowerShell):${C_RESET}"
  body "  ${C_CYAN}type \$env:USERPROFILE\\.ssh\\id_ed25519.pub | ssh -p $SSH_PORT $USERNAME@$vps_ip \"mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys\"${C_RESET}"
  body ""
  body "${C_BOLD}Verify in a NEW terminal:${C_RESET}"
  body "  ${C_CYAN}ssh -p $SSH_PORT $USERNAME@$vps_ip${C_RESET}"
  rail

  local choice
  prompt_radio "What now?" choice \
    "ok|lock down — disable password auth (key must already be on the server)" \
    "skip|keep password auth on, lock down later"

  case "$choice" in
    ok)
      if [[ ! -s "$auth_keys" ]]; then
        warn "No key found at $auth_keys. Push it first, then run: $(harden_command)"
        return 0
      fi
      if ! ssh-keygen -l -f "$auth_keys" >/dev/null 2>&1; then
        warn "$auth_keys exists but contains no valid SSH key. Skipping lockdown."
        warn "Fix the key, then run: $(harden_command)"
        return 0
      fi
      # belt-and-suspenders perms
      chown -R "$USERNAME:$USERNAME" "$user_home/.ssh"
      chmod 700 "$user_home/.ssh"
      chmod 600 "$auth_keys"
      lockdown_ssh
      ;;
    skip)
      # nothing to do — the verifier surfaces the "password auth still on"
      # warning, and `harden` is the supported way back to a locked-down host
      :
      ;;
  esac
}

# ════════════════════════════════════════════════════════════════════════════
# Validation
# ════════════════════════════════════════════════════════════════════════════

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
  [[ "$key" != "sudo_nopasswd" || "${USERNAME:-root}" != "root" ]]
}

add_docker_group_if_needed() {
  if [[ "$USERNAME" != "root" ]]; then
    usermod -aG docker "$USERNAME"
  fi
}

valid_username() {
  [[ "$1" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

valid_port() {
  [[ "$1" =~ ^[0-9]{1,5}$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 ))
}

valid_install_port() {
  # Keep valid_port compatible with recorded legacy installations on :22.
  [[ ! "$1" =~ ^0*22$ ]] && valid_port "$1"
}

selection_allows_port() {
  local port=$1
  shift
  valid_install_port "$port" || return 1
  [[ " $* " != *" caddy "* ]] || (( 10#$port != 80 && 10#$port != 443 ))
}

random_port() {
  # /dev/urandom 16-bit value, mapped into [PORT_MIN, PORT_MAX]
  local n
  n=$(od -An -N2 -tu2 /dev/urandom | tr -d ' \n')
  local range=$(( PORT_MAX - PORT_MIN + 1 ))
  echo $(( PORT_MIN + n % range ))
}

# ════════════════════════════════════════════════════════════════════════════
# cmd_install — the wizard + run + enrollment + auto-check
# ════════════════════════════════════════════════════════════════════════════

cmd_install() {
  [[ $EUID -eq 0 ]] || die "Must run as root."

  [[ ! -e "$STATE_CONFIG" && ! -e "$JOURNAL_DIR/intent" && ! -e "$STATE_FILE" ]] \
    || die "An installation already exists. Use resume (or check/harden for legacy state)."
  local arg_user=${1:-}
  local arg_port=${2:-}

  [[ ! -L "$LOG_FILE" ]] || die "Refusing a symlink log file."
  ( umask 077; : > "$LOG_FILE" )
  banner

  section "About"
  body "vps-boot will harden SSH, set up UFW + fail2ban, and install your"
  body "selected dev tools. Run as root (default) or create a sudo user."
  rail

  # ── user account ──
  local user_mode
  prompt_radio "User account" user_mode \
    "skip|run everything as root (best for autonomous AI environments)" \
    "create|create a sudo user"
  configure_user_mode "$user_mode"

  if (( CREATE_USER )); then
    while :; do
      prompt_text "Username" USERNAME "$arg_user"
      if ! valid_username "$USERNAME"; then
        printf '%s│%s  %s! invalid username — must match [a-z_][a-z0-9_-]{0,31}%s\n' \
          "$C_DIM" "$C_RESET" "$C_YELLOW" "$C_RESET"
        arg_user=""
        continue
      fi
      if id "$USERNAME" &>/dev/null; then
        printf '%s│%s  %s! user %s already exists — pick another%s\n' \
          "$C_DIM" "$C_RESET" "$C_YELLOW" "$USERNAME" "$C_RESET"
        arg_user=""
        continue
      fi
      break
    done

    prompt_password "Password for $USERNAME" USER_PASSWORD
  fi

  # ── port ──
  local port_default=${arg_port:-$(random_port)}
  while :; do
    prompt_text "SSH port" SSH_PORT "$port_default"
    if ! valid_install_port "$SSH_PORT"; then
      printf '%s│%s  %s! choose a port from 1-65535, excluding SSH port 22%s\n' \
        "$C_DIM" "$C_RESET" "$C_YELLOW" "$C_RESET"
      port_default=$(random_port)
      continue
    fi
    SSH_PORT=$((10#$SSH_PORT))
    break
  done

  # ── install mode ──
  local mode
  prompt_radio "Install mode" mode \
    "$(full_install_option)" \
    "Custom|pick what you need"

  # ── component selection ──
  local -a enabled=()
  if [[ "$mode" == "Custom" ]]; then
    local -a msel_args=()
    local key
    for key in "${COMPONENTS[@]}"; do
      component_is_applicable "$key" || continue
      msel_args+=("${key}|${COMPONENT_NAME[$key]}|${COMPONENT_DESC[$key]}|${COMPONENT_DEFAULT[$key]}|${COMPONENT_GROUP[$key]}")
    done
    prompt_multiselect "Components" "${msel_args[@]}"
    enabled=("${PROMPT_MSEL_RESULT[@]}")
  else
    read -r -a enabled <<< "$(full_install_keys)"
  fi

  local resolved
  resolved=$(resolve_components "${enabled[@]}") || die "Cannot resolve component dependencies."
  enabled=(); [[ -z "$resolved" ]] || mapfile -t enabled <<< "$resolved"

  while ! selection_allows_port "$SSH_PORT" "${enabled[@]}"; do
    warn "Choose an SSH port other than 22; Caddy also reserves 80 and 443."
    prompt_text "SSH port" SSH_PORT "$(random_port)"
  done
  SSH_PORT=$((10#$SSH_PORT))

  # ── confirm ──
  section "Confirm"
  if (( CREATE_USER )); then
    body "${C_BOLD}user${C_RESET}      $USERNAME (sudo · docker group if selected)"
    body "${C_BOLD}ssh${C_RESET}       :$SSH_PORT, root login off"
  else
    body "${C_BOLD}user${C_RESET}      root (no sudo user)"
    body "${C_BOLD}ssh${C_RESET}       :$SSH_PORT, root login on until key lockdown"
  fi
  if [[ " ${enabled[*]} " == *" caddy "* ]]; then
    body "${C_BOLD}firewall${C_RESET}  UFW — SSH $SSH_PORT/tcp + Caddy 80/443 TCP"
  else
    body "${C_BOLD}firewall${C_RESET}  UFW — only $SSH_PORT/tcp open"
  fi
  if (( ${#enabled[@]} == 0 )); then
    body "${C_BOLD}install${C_RESET}   ${C_DIM}(none — baseline only)${C_RESET}"
  else
    # bounded: group counts for a full selection, the shorter half otherwise.
    # "│  install   " is 13 visible characters.
    local -a applicable=()
    read -r -a applicable <<< "$(applicable_components)"
    body "${C_BOLD}install${C_RESET}   $(selection_summary \
      "$(( $(term_cols) - 13 ))" "${applicable[*]}" "${enabled[*]}")"
  fi
  rail

  local go
  prompt_radio "Continue?" go \
    "Continue|run the install" \
    "Abort|exit without changes"

  if [[ "$go" != "Continue" ]]; then
    die "Aborted by user."
  fi

  initialize_journal
  run_install
}

run_install() {
  # Both cleanups are armed together, before either setup step runs, so a
  # failure partway through setup (or any step after it) still restores the
  # apt timers and drops the lock-timeout fragment — see cmd_install_cleanup.
  # HUP/INT/TERM are trapped explicitly, alongside EXIT: bash's default
  # disposition for an untrapped fatal signal is to terminate the process
  # immediately, bypassing the EXIT trap entirely — that gap is what stranded
  # the apt timers stopped when an SSH connection dropped while
  # enroll_ssh_key's prompt was waiting on /dev/tty. cmd_install_handle_signal
  # disarms every trap before running cleanup (so its own `exit` cannot
  # re-fire the EXIT trap and double-run cleanup) and exits with the shell's
  # conventional 128+signum status, so the run is reported as killed, not
  # successful.
  trap cmd_install_cleanup EXIT
  trap 'cmd_install_handle_signal HUP'  HUP
  trap 'cmd_install_handle_signal INT'  INT
  trap 'cmd_install_handle_signal TERM' TERM
  stop_apt_timers
  install_apt_lock_timeout

  # ════════════════════════════════════════════════════════════════════
  # Run phase
  # ════════════════════════════════════════════════════════════════════
  section "Installing"

  export DEBIAN_FRONTEND=noninteractive

  journal_step update "System update" bl_update
  journal_step unattended "Automatic security updates" bl_unattended
  if (( CREATE_USER )); then
    journal_step user "User $USERNAME" bl_user
    USER_PASSWORD=""
  fi
  journal_step network "Firewall and SSH" configure_network
  # The port is real from here on, so record it before anything else can fail or
  # be killed — `harden` reads this to re-run the lockdown without arguments.
  # A step of its own rather than a bare call: a failure here has to be visible,
  # since everything downstream of the enrollment prompt depends on it.
  step_run "Recording install state"     write_state_config
  journal_step fail2ban "fail2ban" bl_fail2ban

  local key
  for key in "${enabled[@]}"; do
    journal_step "$key" "${COMPONENT_NAME[$key]}" "${COMPONENT_INSTALL[$key]}"
  done

  # password no longer needed in env
  USER_PASSWORD=""

  # Keep the resolved selection atomic (it was initially saved before setup).
  if (( ${#enabled[@]} > 0 )); then
    printf '%s\n' "${enabled[@]}" | atomic_state "$STATE_FILE"
  else
    atomic_state "$STATE_FILE" < /dev/null
  fi

  # ════════════════════════════════════════════════════════════════════
  # Enrollment + auto-check
  # ════════════════════════════════════════════════════════════════════
  enroll_ssh_key

  # Restore *before* the verifier, not after. do_check asserts
  # apt-daily-upgrade.timer is active, and bl_unattended deliberately enables it
  # without --now, so running the verifier inside the window stop_apt_timers
  # holds open reported a false ✗ on every install (issue #49). Safe: no apt
  # invocation exists in do_check or in any check_*, so nothing from here on
  # takes an apt lock. The traps stay armed across do_check — cmd_install_cleanup
  # is idempotent, so the exit-1 path re-running it costs nothing.
  restore_apt_timers
  remove_apt_lock_timeout

  ENABLED_COMPONENTS=("${enabled[@]}")
  do_check
  trap - EXIT HUP INT TERM
}

# cmd_install_cleanup — the EXIT-trap counterpart to stop_apt_timers +
# install_apt_lock_timeout. Armed before either setup step runs so it fires
# on any failure between there and the end of the run phase, not only on the
# happy path (which calls both cleanups directly, then disarms the trap).
cmd_install_cleanup() {
  local failed=0
  restore_apt_timers || failed=1
  remove_apt_lock_timeout || failed=1
  return "$failed"
}

# cmd_install_handle_signal SIGNAME — HUP/INT/TERM handler paired with the
# EXIT trap above. Disarms every trap *first* so cmd_install_cleanup cannot
# run twice (the `exit` below would otherwise re-fire the EXIT trap too), then
# exits with the shell's conventional 128+signum status so a killed run is
# unambiguously reported as failed, never as a silent success.
cmd_install_handle_signal() {
  local sig=$1
  trap - EXIT HUP INT TERM
  cmd_install_cleanup
  case "$sig" in
    HUP)  exit 129 ;;
    INT)  exit 130 ;;
    TERM) exit 143 ;;
    *)    exit 1 ;;
  esac
}

# ════════════════════════════════════════════════════════════════════════════
# cmd_harden — re-runnable SSH key enrollment + lockdown
# ════════════════════════════════════════════════════════════════════════════

# harden_resolve_target [username] — set USERNAME and SSH_PORT for a standalone
# harden run.
#
# The port is never taken from the command line, which is why `harden` has no
# port argument: writing a mistyped Port into the drop-in would move the
# listener off the port the operator is currently connected through. It comes
# from what the host already has — recorded state first, then the managed
# drop-in, then sshd's own effective config.
harden_resolve_target() {
  local arg_user=${1:-}
  read_state_config
  USERNAME=${arg_user:-${STATE_USERNAME:-root}}
  id "$USERNAME" &>/dev/null || die "User '$USERNAME' does not exist."

  SSH_PORT=${STATE_SSH_PORT:-}
  if [[ -z "$SSH_PORT" && -r "$SSHD_DROPIN" ]]; then
    SSH_PORT=$(awk '$1 == "Port" { print $2; exit }' "$SSHD_DROPIN")
  fi
  if [[ -z "$SSH_PORT" ]]; then
    # sshd -t/-T refuse to run without this dir — see validate_sshd_policy
    install -d -m 0755 /run/sshd 2>/dev/null || true
    SSH_PORT=$(sshd_effective_value port || true)
  fi
  valid_port "${SSH_PORT:-}" \
    || die "Cannot determine this host's SSH port — check $SSHD_DROPIN."
}

# harden_report — the closing verdict for a harden run. Reads the live policy
# rather than lockdown_ssh's exit code, so a skipped or refused lockdown is
# reported as pending instead of silently looking like success.
harden_report() {
  PASS=0; FAIL=0; WARN=0
  rail
  if hardening_is_applied; then
    if [[ "$USERNAME" == "root" ]]; then
      ok "root login restricted to SSH keys"
    else
      ok "root login disabled"
    fi
    ok "password auth disabled"
    done_section "Hardened — ${C_GREEN}keys only${C_RESET} on port $SSH_PORT"
  else
    note "password auth still enabled"
    done_section "Pending — ${C_YELLOW}password auth is still on${C_RESET}"
    body ""
    body "Push your key, then run this again:"
    body "  ${C_CYAN}$(harden_command)${C_RESET}"
  fi
  printf '\n'
}

# cmd_harden [username] — enrollment + lockdown as its own command. Idempotent
# and short, so a dropped connection costs nothing: reconnect and run it again.
cmd_harden() {
  [[ $EUID -eq 0 ]] || die "Must run as root."

  harden_resolve_target "${1:-}"
  banner
  enroll_ssh_key "Enroll your SSH key and lock down"
  # Re-record: a legacy install, or one whose username came from argv, has no
  # state file yet — after this the next run needs no arguments either.
  write_state_config
  harden_report
}

# ════════════════════════════════════════════════════════════════════════════
# cmd_check — verifier (also called inline at end of cmd_install)
# ════════════════════════════════════════════════════════════════════════════

cmd_check() {
  [[ $EUID -eq 0 ]] || die "Must run as root."
  # Recorded state beats the hardcoded fallback: checking against a port the
  # host is not on reports a wall of ✗ that says nothing about the host.
  read_state_config
  USERNAME=${1:-${STATE_USERNAME:-root}}
  SSH_PORT=${2:-${STATE_SSH_PORT:-1986}}
  id "$USERNAME" &>/dev/null || die "User '$USERNAME' does not exist."
  valid_port "$SSH_PORT" || die "Invalid SSH port: $SSH_PORT"

  banner
  if [[ -f "$STATE_FILE" ]]; then
    mapfile -t ENABLED_COMPONENTS < "$STATE_FILE"
    # filter out empty lines
    local -a filtered=()
    local k
    for k in "${ENABLED_COMPONENTS[@]}"; do
      [[ -n "$k" ]] || continue
      component_is_applicable "$k" || continue
      if [[ -z ${COMPONENT_CHECK[$k]:-} ]]; then
        warn "Unknown recorded component: $k"
        continue
      fi
      filtered+=("$k")
    done
    ENABLED_COMPONENTS=("${filtered[@]}")
  else
    # no state — check every registered component
    ENABLED_COMPONENTS=()
    local k
    for k in "${COMPONENTS[@]}"; do
      component_is_applicable "$k" || continue
      ENABLED_COMPONENTS+=("$k")
    done
  fi
  do_check
}

# do_check_unattended — the automatic-security-updates assertion, split in two.
# The old single message ("not configured or timer inactive") conflated causes
# that mean opposite things: a config that never landed is a failed install,
# while a config that is right with the timer stopped is cleanup that was killed
# before restore_apt_timers ran. The operator had to read the source to tell.
do_check_unattended() {
  if ! grep -q '^APT::Periodic::Unattended-Upgrade "1";$' \
       "$UNATTENDED_UPGRADES_CONFIG" 2>/dev/null; then
    ko "unattended-upgrades not configured"
  elif ! systemctl is-active --quiet apt-daily-upgrade.timer 2>/dev/null; then
    ko "unattended-upgrades on, apt-daily-upgrade.timer inactive"
  else
    ok "unattended-upgrades configured, timer active"
  fi
}

do_check() {
  PASS=0; FAIL=0; WARN=0

  section "Verify"

  # ── user ──
  if [[ "$USERNAME" == "root" ]]; then
    ok "root account selected (no sudo user)"
  elif id -nG "$USERNAME" 2>/dev/null | tr ' ' '\n' | grep -qx sudo; then
    ok "$USERNAME in sudo group"
  else
    ko "$USERNAME not in sudo group"
  fi

  # ── ssh ──
  # Retry briefly: the listener can blip during a service reload (fail2ban,
  # daemon-reload) and a one-shot check would falsely flag ✗.
  local i listening=0
  for ((i=0; i<5; i++)); do
    if ssh_listener "$SSH_PORT"; then
      listening=1
      break
    fi
    sleep 1
  done
  if (( listening )); then
    ok "sshd listening on $SSH_PORT"
  else
    ko "sshd not listening on $SSH_PORT"
  fi
  if ss -tlnH 2>/dev/null | awk '{print $4}' | grep -qE '[:.]22$'; then
    ko "something still listening on :22"
  else
    ok "port 22 closed"
  fi
  local permit_root
  permit_root=$(sshd_effective_value permitrootlogin || true)
  if [[ "$USERNAME" == "root" ]]; then
    if sshd_root_is_key_only "$permit_root"; then
      ok "root login restricted to SSH keys"
    else
      # the runnable command goes in the footer, not here: harden_command's
      # curl form is ~110 columns and a wrapped status line loses its rail
      note "root password login still enabled — run 'harden'"
    fi
  elif [[ "$permit_root" == "no" ]]; then
    ok "root login disabled"
  else
    ko "PermitRootLogin not 'no'"
  fi
  if [[ $(systemctl is-enabled ssh.socket 2>/dev/null || true) != masked ]]; then
    ko "ssh.socket is not masked"
  else
    ok "ssh.socket masked/inactive"
  fi
  if systemctl is-active --quiet ssh.service 2>/dev/null; then
    ok "ssh.service active"
  else
    ko "ssh.service not active"
  fi
  install -d -m 0755 /run/sshd
  if sshd -t 2>/dev/null; then
    ok "sshd config valid"
  else
    ko "sshd config invalid"
  fi
  local pa kbd
  pa=$(sshd_effective_value passwordauthentication || true)
  kbd=$(sshd_effective_value kbdinteractiveauthentication || true)
  if [[ "$pa" == "no" && "$kbd" == "no" ]]; then
    ok "password auth disabled"
  elif [[ "$pa" != "$kbd" ]]; then
    ko "password authentication methods disagree (password=$pa, keyboard-interactive=$kbd)"
  else
    note "password auth still enabled — run 'harden'"
  fi
  local user_home auth_keys
  user_home=$(getent passwd "$USERNAME" | cut -d: -f6)
  auth_keys="$user_home/.ssh/authorized_keys"
  if [[ -s "$auth_keys" ]] && ssh-keygen -l -f "$auth_keys" >/dev/null 2>&1; then
    local kc
    kc=$(ssh-keygen -l -f "$auth_keys" 2>/dev/null | wc -l)
    ok "$kc SSH key(s) enrolled for $USERNAME"
  else
    note "no SSH key enrolled for $USERNAME"
  fi

  # ── ufw ──
  if ufw status 2>/dev/null | grep -q "Status: active"; then
    ok "UFW active"
  else
    ko "UFW inactive"
  fi
  if ufw status 2>/dev/null | grep -qE "^${SSH_PORT}/tcp[[:space:]]+ALLOW"; then
    ok "$SSH_PORT/tcp allowed"
  else
    ko "$SSH_PORT/tcp not allowed"
  fi

  # ── fail2ban ──
  if systemctl is-active --quiet fail2ban; then
    ok "fail2ban running"
  else
    ko "fail2ban not running"
  fi
  if fail2ban-client status sshd >/dev/null 2>&1; then
    ok "sshd jail active"
  else
    ko "sshd jail not active"
  fi

  # ── unattended upgrades ──
  do_check_unattended
  if [[ -e /var/run/reboot-required ]]; then
    note "reboot required — a pending update needs a reboot to take effect"
  fi

  # ── components ──
  local key
  for key in "${ENABLED_COMPONENTS[@]}"; do
    "${COMPONENT_CHECK[$key]}"
  done

  # ── summary ──
  rail
  local color="$C_GREEN"
  (( FAIL > 0 )) && color="$C_RED"
  (( FAIL == 0 && WARN > 0 )) && color="$C_YELLOW"

  done_section "Done — ${color}${PASS} passed${C_RESET}, ${color}${FAIL} failed${C_RESET}, ${color}${WARN} warning(s)${C_RESET}"

  do_check_footer

  (( FAIL == 0 )) || exit 1
}

# do_check_footer — the what-now block under the verifier summary: how to
# connect, how to finish hardening if it is still pending, and the components'
# own sign-in hints. Split out from do_check because it is pure presentation
# and can be exercised without a live host underneath it.
do_check_footer() {
  local vps_ip
  vps_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  [[ -z "$vps_ip" ]] && vps_ip="<vps-ip>"

  body ""
  body "${C_BOLD}Connect:${C_RESET}  ssh -p $SSH_PORT $USERNAME@$vps_ip"

  # The notes above only flag an open box; this is the line that closes it.
  # The command lives here rather than in the note because harden_command's
  # curl form is ~110 columns and a wrapped status line loses its rail.
  if ! hardening_is_applied; then
    body "${C_BOLD}Harden:${C_RESET}   password auth is still on — run:"
    body "          ${C_CYAN}$(harden_command)${C_RESET}"
  fi

  # ── post-install sign-in hints (component-owned, optional) ──
  local -a hints=()
  local k
  for k in "${ENABLED_COMPONENTS[@]}"; do
    [[ -n "${COMPONENT_SIGNIN[$k]:-}" ]] && hints+=("${COMPONENT_SIGNIN[$k]}")
  done
  if (( ${#hints[@]} > 0 )); then
    body "${C_BOLD}Sign in:${C_RESET}  ${hints[0]}"
    local i
    for ((i=1; i<${#hints[@]}; i++)); do
      body "          ${hints[i]}"
    done
  fi

  if [[ "$USERNAME" != "root" && " ${ENABLED_COMPONENTS[*]} " == *" docker "* ]]; then
    body "${C_DIM}Note: docker group membership requires a fresh login.${C_RESET}"
  fi
  printf '\n'
}

# ════════════════════════════════════════════════════════════════════════════
# Entry point
# ════════════════════════════════════════════════════════════════════════════

cmd_help() {
  cat <<EOF
${C_BOLD}vps-boot${C_RESET} — resumable Ubuntu 26.04 amd64 hardening + dev toolchain

${C_BOLD}USAGE${C_RESET}
  sudo $0 install [username] [port]
  sudo $0 resume
  sudo $0 harden  [username]
  sudo $0 check   [username] [port]
  sudo $0 --help

${C_BOLD}COMMANDS${C_RESET}
  install   Run the interactive wizard as root (default) or create a sudo user.
            Args (optional) pre-fill the created username and SSH port prompts.
  resume    Resume the recorded installation; verified components are retained.
  harden    Re-run SSH key enrollment and lockdown. Idempotent, safe any time.
            The username defaults to what install recorded in $STATE_CONFIG.
  check     Re-run the verifier on an existing vps-boot install.
            Args (optional) default to what install recorded in $STATE_CONFIG,
            then to root and SSH port 1986.

${C_BOLD}REMOTE${C_RESET}
  curl -fsSL $REMOTE_URL \\
    | sudo bash -s install

  Run it under tmux or screen: the install takes ~45 minutes and the enrollment
  prompt waits on you, so a dropped connection is expected rather than rare.
  If one does drop, reconnect and finish with:

  curl -fsSL $REMOTE_URL \\
    | sudo bash -s harden

EOF
}

main() {
  local cmd=${1:-install}
  case "$cmd" in
    install)
      (( $# == 0 )) || shift
      (( $# <= 2 )) || die "install accepts at most username and port."
      preflight
      acquire_install_lock
      cmd_install "$@"
      ;;
    resume)
      shift
      (( $# == 0 )) || die "resume takes no arguments."
      preflight
      acquire_install_lock
      cmd_resume
      ;;
    --version|version)
      (( $# == 1 )) || die "version takes no arguments."
      printf '%s\n' "$VPS_BOOT_VERSION"
      ;;
    harden)
      shift
      (( $# <= 1 )) || die "harden accepts at most username."
      [[ $EUID -eq 0 ]] || die "Must run as root."
      acquire_install_lock
      cmd_harden "$@"
      ;;
    check)
      shift
      (( $# <= 2 )) || die "check accepts at most username and port."
      cmd_check "$@"
      ;;
    -h|--help|help)
      cmd_help
      ;;
    *)
      die "unknown command: $cmd — try '$0 --help'"
      ;;
  esac
}

if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]:-}" == "$0" ]]; then
  main "$@"
fi
