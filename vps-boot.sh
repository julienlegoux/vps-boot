#!/usr/bin/env bash
# vps-boot.sh — single-shot Ubuntu LTS hardening + dev toolchain
# Usage: sudo ./vps-boot.sh install [username] [port]
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
readonly PORT_MAX=65535
readonly LOG_FILE="${VPS_BOOT_LOG_FILE:-/tmp/vps-boot.log}"
readonly APT_LOCK_TIMEOUT=180
readonly APT_LOCK_CONFIG="${VPS_BOOT_APT_LOCK_CONFIG:-/etc/apt/apt.conf.d/99-vps-boot-lock-timeout}"
readonly UNATTENDED_UPGRADES_CONFIG="${VPS_BOOT_UNATTENDED_UPGRADES_CONFIG:-/etc/apt/apt.conf.d/20auto-upgrades}"
readonly SUDOERS_DIR="${VPS_BOOT_SUDOERS_DIR:-/etc/sudoers.d}"
readonly SSHD_CONFIG="${VPS_BOOT_SSHD_CONFIG:-/etc/ssh/sshd_config}"
readonly SSHD_DROPIN="${VPS_BOOT_SSHD_DROPIN:-/etc/ssh/sshd_config.d/00-vps-boot.conf}"
readonly STATE_DIR="${VPS_BOOT_STATE_DIR:-/etc/vps-boot}"
readonly STATE_FILE="$STATE_DIR/components"

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

# section "Title" — opens a new section with diamond + orange title + rule
section() {
  local title=$1
  local width
  width=$(tput cols 2>/dev/null || echo 80)
  local prefix_len=4   # "◇  " is 3 visible chars + 1 trailing space
  local title_len=${#title}
  local fill=$(( width - prefix_len - title_len - 2 ))
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

# prompt_radio "label" out_var "option1|desc1" "option2|desc2" ...
# Selected option key is stored in the named variable.
prompt_radio() {
  local label=$1
  local out_var=$2
  shift 2
  local -a keys=()
  local -a descs=()
  local opt key desc
  for opt in "$@"; do
    key=${opt%%|*}
    desc=${opt#*|}
    [[ "$desc" == "$opt" ]] && desc=""
    keys+=("$key")
    descs+=("$desc")
  done
  local n=${#keys[@]}
  local current=0

  printf '\n%s◇%s  %s%s%s\n' "$C_ORANGE" "$C_RESET" "$C_BOLD" "$label" "$C_RESET"
  printf '%s│%s  %s(↑/↓ to move, enter to confirm)%s\n' "$C_DIM" "$C_RESET" "$C_DIM" "$C_RESET"

  _radio_draw() {
    local i
    for ((i=0; i<n; i++)); do
      printf '%s│%s  ' "$C_DIM" "$C_RESET"
      if (( i == current )); then
        printf '%s●%s %s%s%s' "$C_CYAN" "$C_RESET" "$C_BOLD" "${keys[i]}" "$C_RESET"
      else
        printf '%s○%s %s' "$C_DIM" "$C_RESET" "${keys[i]}"
      fi
      if [[ -n "${descs[i]}" ]]; then
        printf '   %s%s%s' "$C_DIM" "${descs[i]}" "$C_RESET"
      fi
      printf '\n'
    done
  }

  _radio_draw

  local k rest
  while :; do
    IFS= read -rsn1 k < /dev/tty || break
    case "$k" in
      $'\033')
        IFS= read -rsn2 -t 0.05 rest < /dev/tty || rest=""
        case "$rest" in
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

    # redraw — move up n lines and rewrite each
    printf '\033[%dA' "$n"
    local i
    for ((i=0; i<n; i++)); do
      printf '\033[2K'
      printf '%s│%s  ' "$C_DIM" "$C_RESET"
      if (( i == current )); then
        printf '%s●%s %s%s%s' "$C_CYAN" "$C_RESET" "$C_BOLD" "${keys[i]}" "$C_RESET"
      else
        printf '%s○%s %s' "$C_DIM" "$C_RESET" "${keys[i]}"
      fi
      if [[ -n "${descs[i]}" ]]; then
        printf '   %s%s%s' "$C_DIM" "${descs[i]}" "$C_RESET"
      fi
      printf '\n'
    done
  done

  # collapse: clear hint + options, reprint just the chosen value
  printf '\033[%dA\033[J' "$(( n + 1 ))"
  printf '%s│%s  %s●%s %s%s%s\n' "$C_DIM" "$C_RESET" "$C_GREEN" "$C_RESET" "$C_BOLD" "${keys[current]}" "$C_RESET"

  printf -v "$out_var" '%s' "${keys[current]}"
}

# prompt_multiselect "label" out_var_array "key1|name1|desc1|default1" ...
# default1 is 1 (checked) or 0 (unchecked).
# Selected keys are written to the named array variable.
PROMPT_MSEL_RESULT=()
prompt_multiselect() {
  local label=$1
  shift
  local -a keys=() names=() descs=() selected=()
  local opt key name desc def
  for opt in "$@"; do
    IFS='|' read -r key name desc def <<<"$opt"
    keys+=("$key")
    names+=("$name")
    descs+=("$desc")
    selected+=("$def")
  done
  local n=${#keys[@]}
  local current=0

  printf '\n%s◇%s  %s%s%s\n' "$C_ORANGE" "$C_RESET" "$C_BOLD" "$label" "$C_RESET"
  printf '%s│%s  %s(↑/↓ to move, space to toggle, enter to confirm)%s\n' "$C_DIM" "$C_RESET" "$C_DIM" "$C_RESET"

  local i
  for ((i=0; i<n; i++)); do
    _msel_print_line "$i"
  done

  local k rest
  while :; do
    IFS= read -rsn1 k < /dev/tty || break
    case "$k" in
      $'\033')
        IFS= read -rsn2 -t 0.05 rest < /dev/tty || rest=""
        case "$rest" in
          '[A') current=$(( (current - 1 + n) % n )) ;;
          '[B') current=$(( (current + 1) % n )) ;;
        esac
        ;;
      ' ') selected[current]=$(( 1 - selected[current] )) ;;
      '') break ;;
      'k') current=$(( (current - 1 + n) % n )) ;;
      'j') current=$(( (current + 1) % n )) ;;
    esac

    printf '\033[%dA' "$n"
    for ((i=0; i<n; i++)); do
      printf '\033[2K'
      _msel_print_line "$i"
    done
  done

  # collapse to summary
  printf '\033[%dA\033[J' "$(( n + 1 ))"
  PROMPT_MSEL_RESULT=()
  local first=1 summary="│  "
  for ((i=0; i<n; i++)); do
    if (( selected[i] )); then
      PROMPT_MSEL_RESULT+=("${keys[i]}")
      if (( first )); then
        summary+="${C_GREEN}●${C_RESET} ${C_BOLD}${names[i]}${C_RESET}"
        first=0
      else
        summary+=" ${C_DIM}·${C_RESET} ${names[i]}"
      fi
    fi
  done
  if (( first )); then
    printf '%s│%s  %s(none selected)%s\n' "$C_DIM" "$C_RESET" "$C_DIM" "$C_RESET"
  else
    printf '%s%s\n' "$C_DIM" "${summary#│  }" | sed "s|^|${C_DIM}│${C_RESET}  |"
  fi
}

_msel_print_line() {
  local i=$1
  local glyph
  if (( ${selected[i]} )); then glyph="${C_GREEN}◉${C_RESET}"; else glyph="${C_DIM}◌${C_RESET}"; fi

  if (( i == current )); then
    printf '%s│%s %s›%s %s ' "$C_DIM" "$C_RESET" "$C_CYAN" "$C_RESET" "$glyph"
    printf '%s%s%s' "$C_CYAN$C_BOLD" "${names[i]}" "$C_RESET"
  else
    printf '%s│%s   %s ' "$C_DIM" "$C_RESET" "$glyph"
    printf '%s' "${names[i]}"
  fi
  if [[ -n "${descs[i]}" ]]; then
    printf '   %s%s%s' "$C_DIM" "${descs[i]}" "$C_RESET"
  fi
  printf '\n'
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
  apt install -y jq ripgrep fd-find htop tree

  # fd-find is packaged as 'fdfind' on Debian/Ubuntu to avoid collision with the
  # 'fd' package (a different tool). Expose the common name 'fd' via update-alternatives
  # so scripts and users can reach it by its standard name.
  update-alternatives --install /usr/local/bin/fd fd /usr/bin/fdfind 1
}

check_tools() {
  local failures=0
  local versions=()

  # Check jq
  if command -v jq >/dev/null 2>&1; then
    local v
    v=$(jq --version 2>/dev/null | head -1 || echo "?")
    versions+=("jq $v")
  else
    versions+=("jq ✗")
    ((failures++))
  fi

  # Check ripgrep (rg)
  if command -v rg >/dev/null 2>&1; then
    local v
    v=$(rg --version 2>/dev/null | head -1 | awk '{print $2}' || echo "?")
    versions+=("rg $v")
  else
    versions+=("rg ✗")
    ((failures++))
  fi

  # Check fd (via the update-alternatives link)
  if command -v fd >/dev/null 2>&1; then
    local v
    v=$(fd --version 2>/dev/null | head -1 || echo "?")
    versions+=("fd $v")
  else
    versions+=("fd ✗")
    ((failures++))
  fi

  # Check htop
  if command -v htop >/dev/null 2>&1; then
    local v
    v=$(htop --version 2>/dev/null | head -1 || echo "?")
    versions+=("htop $v")
  else
    versions+=("htop ✗")
    ((failures++))
  fi

  # Check tree
  if command -v tree >/dev/null 2>&1; then
    local v
    v=$(tree --version 2>/dev/null | head -1 || echo "?")
    versions+=("tree $v")
  else
    versions+=("tree ✗")
    ((failures++))
  fi

  if (( failures == 0 )); then
    ok "tools: ${versions[*]}"
  else
    ko "tools: ${versions[*]}"
  fi
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
  apt update -y
  apt install -y \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
  add_docker_group_if_needed
}

check_docker() {
  if systemctl is-active --quiet docker; then
    local v
    v=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',' || echo "?")
    local cv
    cv=$(docker compose version --short 2>/dev/null || echo "?")
    ok "docker $v · compose v$cv"
  else
    ko "docker daemon not running"
  fi
  if [[ "$USERNAME" != "root" ]]; then
    if id -nG "$USERNAME" 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
      ok "$USERNAME in docker group"
    else
      ko "$USERNAME not in docker group"
    fi
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
  apt update -y
  apt install -y gh
}

check_gh() {
  if command -v gh >/dev/null 2>&1; then
    local v
    v=$(gh --version 2>/dev/null | head -1 | awk '{print $3}' || echo "?")
    ok "gh $v"
  else
    ko "gh not installed"
  fi
}

register gh "GitHub CLI" "gh" 1 system core install_gh check_gh \
  "gh auth login            (paste the one-time code in your browser)"

# ══ languages ═════════════════════════════════════════════

# ─── node ──────────────────────────────────────────────────
install_node() {
  curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
  apt install -y nodejs
}

check_node() {
  if command -v node >/dev/null 2>&1; then
    local v
    v=$(node --version 2>/dev/null || echo "?")
    ok "node $v"
  else
    ko "node not installed"
  fi
}

register node "Node LTS" "current LTS via NodeSource" 1 system languages install_node check_node

# ─── python ────────────────────────────────────────────────
install_python() {
  add-apt-repository -y ppa:deadsnakes/ppa
  apt update -y

  # Pick the newest python3.X that actually has an installable candidate.
  # Deadsnakes lists pre-release names (e.g. 3.15) before the binary is shipped
  # for the current Ubuntu release, so we have to probe with --dry-run.
  local pyver="" v
  for v in $(apt-cache search '^python3\.[0-9]+$' \
              | grep -oP 'python3\.\d+' \
              | sort -t. -k2 -n -r); do
    if apt install -y --dry-run "$v" "${v}-venv" >/dev/null 2>&1; then
      pyver="$v"
      break
    fi
  done
  [ -n "$pyver" ] || { echo "no installable Python found in deadsnakes PPA" >&2; return 1; }

  # distutils was removed from stdlib in 3.12 and deadsnakes no longer ships
  # python3.X-distutils for newer versions, so we don't install it.
  apt install -y "$pyver" "${pyver}-venv"

  # Bootstrap pip for the new interpreter via ensurepip (ships with python3.X-venv).
  # python3-pip would only wire pip to the system Python, not our $pyver.
  "/usr/bin/$pyver" -m ensurepip --upgrade --default-pip

  # Do NOT repoint /usr/bin/python3 — distro packages (fail2ban, apt itself,
  # etc.) are built against the system Python and break under a newer
  # interpreter (e.g. sre_constants was removed in 3.13). Only expose the
  # new interpreter as `python` for interactive use.
  update-alternatives --install /usr/bin/python python "/usr/bin/$pyver" 1
}

check_python() {
  # Report the `python` alternative (deadsnakes interpreter) rather than
  # `python3` (system Python), since the install step deliberately leaves
  # /usr/bin/python3 alone to avoid breaking distro services.
  if command -v python >/dev/null 2>&1; then
    local v
    v=$(python --version 2>/dev/null | awk '{print $2}' || echo "?")
    ok "python $v"
  else
    ko "python not installed"
  fi
  local py_bin
  py_bin=$(command -v python || true)
  if [ -n "$py_bin" ] && "$py_bin" -m pip --version >/dev/null 2>&1; then
    local pv
    pv=$("$py_bin" -m pip --version 2>/dev/null | awk '{print $2}' || echo "?")
    ok "pip $pv"
  else
    ko "pip not installed"
  fi
}

register python "Python + pip" "latest Python 3 via deadsnakes PPA" 1 system languages install_python check_python

# ─── go ────────────────────────────────────────────────────
install_go() {
  local ver arch
  ver=$(curl -fsSL "https://go.dev/VERSION?m=text" | head -1)
  arch=$(dpkg --print-architecture)
  rm -rf /usr/local/go
  curl -fsSL "https://go.dev/dl/${ver}.linux-${arch}.tar.gz" \
    | tar -C /usr/local -xz
  printf 'export PATH=$PATH:/usr/local/go/bin\n' > /etc/profile.d/go.sh
  chmod 644 /etc/profile.d/go.sh
}

check_go() {
  if [ -x /usr/local/go/bin/go ]; then
    local v
    v=$(/usr/local/go/bin/go version 2>/dev/null | awk '{print $3}' || echo "?")
    ok "go $v"
  else
    ko "go not installed"
  fi
}

register go "Go" "latest Go via go.dev" 1 system languages install_go check_go

# ══ packaging ═════════════════════════════════════════════

# ─── bun ───────────────────────────────────────────────────
install_bun() {
  npm install -g bun
}

check_bun() {
  if command -v bun >/dev/null 2>&1; then
    local v
    v=$(bun --version 2>/dev/null || echo "?")
    ok "bun $v"
  else
    ko "bun not installed"
  fi
}

register bun "Bun" "JS runtime" 1 system packaging install_bun check_bun

# ─── pnpm ──────────────────────────────────────────────────
install_pnpm() {
  npm install -g pnpm
}

check_pnpm() {
  if command -v pnpm >/dev/null 2>&1; then
    local v
    v=$(pnpm --version 2>/dev/null || echo "?")
    ok "pnpm $v"
  else
    ko "pnpm not installed"
  fi
}

register pnpm "pnpm" "fast npm-compatible package manager" 1 system packaging install_pnpm check_pnpm

# ══ agents ════════════════════════════════════════════════

# ─── claude code ───────────────────────────────────────────
install_claude() {
  npm install -g @anthropic-ai/claude-code
}

check_claude() {
  if command -v claude >/dev/null 2>&1; then
    ok "claude code installed"
  else
    ko "claude code not installed"
  fi
}

register claude "Claude Code" "Anthropic's CLI" 1 system agents install_claude check_claude \
  "claude                   (first run opens the OAuth browser flow)"

# ─── opencode ──────────────────────────────────────────────
install_opencode() {
  npm install -g opencode-ai
}

check_opencode() {
  if command -v opencode >/dev/null 2>&1; then
    local v
    v=$(opencode --version 2>/dev/null | head -1 | awk '{print $NF}' || echo "?")
    ok "opencode $v"
  else
    ko "opencode not installed"
  fi
}

register opencode "opencode" "open-source AI coding agent" 1 system agents install_opencode check_opencode \
  "opencode auth login      (pick a provider and paste its API key)"

# ─── hermes ────────────────────────────────────────────────
install_hermes() {
  # Upstream installer shells out to `sudo apt-get install ffmpeg` as
  # $USERNAME, which would prompt. Drop a temporary NOPASSWD rule for the
  # duration of the install and remove it on the way out (success or fail).
  local sudoers=/etc/sudoers.d/99-vps-boot-hermes
  printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$USERNAME" > "$sudoers"
  chmod 440 "$sudoers"
  trap 'rm -f /etc/sudoers.d/99-vps-boot-hermes' RETURN
  sudo -u "$USERNAME" -H bash <<'EOF'
set -eo pipefail
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh \
  | bash -s -- --skip-setup
EOF
  rm -f "$sudoers"
  trap - RETURN
}

check_hermes() {
  local v
  v=$(sudo -u "$USERNAME" -H bash -lc 'command -v hermes >/dev/null 2>&1 && hermes --version 2>/dev/null | head -1' || true)
  if [[ -n "$v" ]]; then
    ok "hermes $v"
  else
    ko "hermes not installed"
  fi
}

register hermes "Hermes" "NousResearch AI agent" 1 user agents install_hermes check_hermes \
  "hermes setup             (configure LLM provider and API keys)"

# ══ cloud ═════════════════════════════════════════════════
# (no components in this group yet)

# ══ infra ═════════════════════════════════════════════════

# ─── herdr ─────────────────────────────────────────────────
install_herdr() {
  # Upstream defaults to $HOME/.local/bin, which is not on PATH for a fresh
  # root-only box. HERDR_INSTALL_DIR pins it system-wide instead, so the
  # binary works for root and any created user alike.
  curl -fsSL https://herdr.dev/install.sh | HERDR_INSTALL_DIR=/usr/local/bin sh
}

check_herdr() {
  if command -v herdr >/dev/null 2>&1; then
    local v
    v=$(herdr --version 2>/dev/null | head -1 | awk '{print $NF}' || echo "?")
    ok "herdr $v"
  else
    ko "herdr not installed"
  fi
}

register herdr "herdr" "agent-aware terminal multiplexer" 1 system infra install_herdr check_herdr

# ════════════════════════════════════════════════════════════════════════════
# Baseline (mandatory, ordered) — NOT registered, always run
# ════════════════════════════════════════════════════════════════════════════

install_apt_lock_timeout() {
  local config_dir candidate=""
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
  rm -f "$APT_LOCK_CONFIG"
}

bl_update() {
  apt update -y
  apt upgrade -y
  apt install -y \
    wget gnupg lsb-release ca-certificates \
    software-properties-common ufw fail2ban git unzip curl sudo \
    build-essential
}

# bl_unattended — installs unattended-upgrades and enables automatic security
# updates only. Automatic-Reboot stays false: rebooting an unattended host out
# from under whatever is running on it is a decision for the operator, not a
# default.
bl_unattended() {
  apt install -y unattended-upgrades

  local config_dir candidate
  config_dir=$(dirname "$UNATTENDED_UPGRADES_CONFIG")
  install -d -m 0755 "$config_dir"
  candidate=$(mktemp "$config_dir/.vps-boot-unattended.XXXXXX")
  if ! cat > "$candidate" <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
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

  systemctl enable --now apt-daily-upgrade.timer >/dev/null 2>&1 || true
}

bl_user() {
  # non-interactive: useradd + chpasswd. password is in $USER_PASSWORD env.
  useradd -m -s /bin/bash -c "" "$USERNAME"
  echo "$USERNAME:$USER_PASSWORD" | chpasswd
  usermod -aG sudo "$USERNAME"
}

bl_ufw() {
  ufw --force reset >/dev/null
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow "$SSH_PORT"/tcp comment 'SSH'
  ufw --force enable
}

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
  apply_sshd_policy "$permit_root" yes yes 0

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
    if ss -tlnH 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${SSH_PORT}\$"; then
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
# SSH key enrollment
# ════════════════════════════════════════════════════════════════════════════

enroll_ssh_key() {
  local user_home auth_keys vps_ip
  user_home=$(getent passwd "$USERNAME" | cut -d: -f6)
  auth_keys="$user_home/.ssh/authorized_keys"
  vps_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  [[ -z "$vps_ip" ]] && vps_ip="<vps-ip>"

  section "Almost done — enroll your SSH key"
  body ""
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
        warn "No key found at $auth_keys. Push it first, then re-run: sudo $0 check $USERNAME $SSH_PORT"
        return 0
      fi
      if ! ssh-keygen -l -f "$auth_keys" >/dev/null 2>&1; then
        warn "$auth_keys exists but contains no valid SSH key. Skipping lockdown."
        return 0
      fi
      # belt-and-suspenders perms
      chown -R "$USERNAME:$USERNAME" "$user_home/.ssh"
      chmod 700 "$user_home/.ssh"
      chmod 600 "$auth_keys"
      lockdown_ssh
      ;;
    skip)
      # nothing to do — verifier will surface the "password auth still on" warning
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
  [[ "$key" != "sudo_nopasswd" || "$USERNAME" != "root" ]]
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
  [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 ))
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

  local arg_user=${1:-}
  local arg_port=${2:-}

  : > "$LOG_FILE"
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
    if ! valid_port "$SSH_PORT"; then
      printf '%s│%s  %s! invalid port — must be 1-65535%s\n' \
        "$C_DIM" "$C_RESET" "$C_YELLOW" "$C_RESET"
      port_default=$(random_port)
      continue
    fi
    if [[ "$SSH_PORT" == "22" ]]; then
      printf '%s│%s  %s! port 22 is the default — using it leaves you at the same exposure level%s\n' \
        "$C_DIM" "$C_RESET" "$C_YELLOW" "$C_RESET"
    fi
    break
  done

  # ── install mode ──
  local mode
  prompt_radio "Install mode" mode \
    "QuickStart|Docker · gh · Node LTS · Bun · Claude Code (defaults)" \
    "Custom|pick which tools to install"

  # ── component selection ──
  local -a enabled=()
  if [[ "$mode" == "Custom" ]]; then
    local -a msel_args=()
    local key
    for key in "${COMPONENTS[@]}"; do
      component_is_applicable "$key" || continue
      msel_args+=("${key}|${COMPONENT_NAME[$key]}|${COMPONENT_DESC[$key]}|${COMPONENT_DEFAULT[$key]}")
    done
    prompt_multiselect "Components" "${msel_args[@]}"
    enabled=("${PROMPT_MSEL_RESULT[@]}")
  else
    # QuickStart — all defaults
    local key
    for key in "${COMPONENTS[@]}"; do
      component_is_applicable "$key" || continue
      [[ "${COMPONENT_DEFAULT[$key]}" == "1" ]] && enabled+=("$key")
    done
  fi

  # ── confirm ──
  section "Confirm"
  if (( CREATE_USER )); then
    body "${C_BOLD}user${C_RESET}      $USERNAME (sudo · docker group if selected)"
    body "${C_BOLD}ssh${C_RESET}       :$SSH_PORT, root login off"
  else
    body "${C_BOLD}user${C_RESET}      root (no sudo user)"
    body "${C_BOLD}ssh${C_RESET}       :$SSH_PORT, root login on until key lockdown"
  fi
  body "${C_BOLD}firewall${C_RESET}  UFW — only $SSH_PORT/tcp open"
  if (( ${#enabled[@]} == 0 )); then
    body "${C_BOLD}install${C_RESET}   ${C_DIM}(none — baseline only)${C_RESET}"
  else
    local list=""
    local k
    for k in "${enabled[@]}"; do
      [[ -n "$list" ]] && list+=" · "
      list+="${COMPONENT_NAME[$k]}"
    done
    body "${C_BOLD}install${C_RESET}   $list"
  fi
  rail

  local go
  prompt_radio "Continue?" go \
    "Continue|run the install" \
    "Abort|exit without changes"

  if [[ "$go" != "Continue" ]]; then
    die "Aborted by user."
  fi

  trap remove_apt_lock_timeout EXIT
  install_apt_lock_timeout

  # ════════════════════════════════════════════════════════════════════
  # Run phase
  # ════════════════════════════════════════════════════════════════════
  section "Installing"

  export DEBIAN_FRONTEND=noninteractive

  step_run "System update"               bl_update
  step_run "Automatic security updates"  bl_unattended
  if (( CREATE_USER )); then
    step_run "User $USERNAME"            bl_user
  fi
  step_run "Firewall (UFW)"              bl_ufw
  step_run "SSH hardening"               bl_ssh_harden
  step_run "fail2ban"                    bl_fail2ban

  local key
  for key in "${enabled[@]}"; do
    step_run "${COMPONENT_NAME[$key]}"   "${COMPONENT_INSTALL[$key]}"
  done

  # password no longer needed in env
  USER_PASSWORD=""

  # persist enabled components so standalone `check` knows what was installed
  mkdir -p "$STATE_DIR"
  if (( ${#enabled[@]} > 0 )); then
    printf '%s\n' "${enabled[@]}" > "$STATE_FILE"
  else
    : > "$STATE_FILE"
  fi

  # ════════════════════════════════════════════════════════════════════
  # Enrollment + auto-check
  # ════════════════════════════════════════════════════════════════════
  enroll_ssh_key

  ENABLED_COMPONENTS=("${enabled[@]}")
  do_check
  remove_apt_lock_timeout
  trap - EXIT
}

# ════════════════════════════════════════════════════════════════════════════
# cmd_check — verifier (also called inline at end of cmd_install)
# ════════════════════════════════════════════════════════════════════════════

cmd_check() {
  [[ $EUID -eq 0 ]] || die "Must run as root."
  USERNAME=${1:-root}
  SSH_PORT=${2:-1986}
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
    if ss -tlnH 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${SSH_PORT}\$"; then
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
      note "root password login still enabled"
    fi
  elif [[ "$permit_root" == "no" ]]; then
    ok "root login disabled"
  else
    ko "PermitRootLogin not 'no'"
  fi
  if systemctl is-active --quiet ssh.socket 2>/dev/null; then
    ko "ssh.socket should be masked but is active"
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
    note "password auth still enabled"
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
  if grep -q '^APT::Periodic::Unattended-Upgrade "1";$' "$UNATTENDED_UPGRADES_CONFIG" 2>/dev/null \
     && systemctl is-active --quiet apt-daily-upgrade.timer 2>/dev/null; then
    ok "unattended-upgrades configured, timer active"
  else
    ko "unattended-upgrades not configured or timer inactive"
  fi
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

  local vps_ip
  vps_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  [[ -z "$vps_ip" ]] && vps_ip="<vps-ip>"

  body ""
  body "${C_BOLD}Connect:${C_RESET}  ssh -p $SSH_PORT $USERNAME@$vps_ip"

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

  (( FAIL == 0 )) || exit 1
}

# ════════════════════════════════════════════════════════════════════════════
# Entry point
# ════════════════════════════════════════════════════════════════════════════

cmd_help() {
  cat <<EOF
${C_BOLD}vps-boot${C_RESET} — single-shot Ubuntu LTS hardening + dev toolchain

${C_BOLD}USAGE${C_RESET}
  sudo $0 install [username] [port]
  sudo $0 check   [username] [port]
  sudo $0 --help

${C_BOLD}COMMANDS${C_RESET}
  install   Run the interactive wizard as root (default) or create a sudo user.
            Args (optional) pre-fill the created username and SSH port prompts.
  check     Re-run the verifier on an existing vps-boot install.
            Args (optional) default to root and SSH port 1986.

${C_BOLD}REMOTE${C_RESET}
  curl -fsSL https://raw.githubusercontent.com/julienlegoux/vps-boot/main/vps-boot.sh \\
    | sudo bash -s install

EOF
}

main() {
  local cmd=${1:-install}
  case "$cmd" in
    install)
      shift
      cmd_install "$@"
      ;;
    check)
      shift
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
