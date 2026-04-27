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

readonly TIMEZONE="Europe/Paris"
readonly NVM_VERSION="v0.40.4"
readonly PORT_MIN=10000
readonly PORT_MAX=65535
readonly LOG_FILE="/tmp/vps-boot.log"
readonly STATE_DIR="/etc/vps-boot"
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

  if "$@" >>"$LOG_FILE" 2>&1; then
    printf '\r%s│%s  %s◆%s  %s ' "$C_DIM" "$C_RESET" "$C_GREEN" "$C_RESET" "$label"
    printf '%s%s%s ' "$C_DIM" "$dotstr" "$C_RESET"
    printf '%s✓%s\n' "$C_GREEN" "$C_RESET"
    return 0
  else
    local rc=$?
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

# prompt_text "label" "default" -> echoes the entered value
# Reads from /dev/tty so it works under `curl | sudo bash`.
prompt_text() {
  local label=$1
  local default=${2:-}
  local input

  printf '\n%s◇%s  %s%s%s\n' "$C_ORANGE" "$C_RESET" "$C_BOLD" "$label" "$C_RESET"
  printf '%s│%s  %s›%s ' "$C_DIM" "$C_RESET" "$C_CYAN" "$C_RESET"

  if [[ -n "$default" ]]; then
    # use readline to pre-fill an editable default
    IFS= read -r -e -i "$default" input < /dev/tty
  else
    IFS= read -r input < /dev/tty
  fi

  printf '%s' "${input:-$default}"
}

# prompt_password "label" -> echoes the password (no terminal echo while typing)
prompt_password() {
  local label=$1
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

  printf '%s' "$pw1"
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

  printf '%s│%s  ' "$C_DIM" "$C_RESET"
  if (( i == current )); then
    printf '%s ' "$glyph"
    printf '%s%s%s' "$C_BOLD" "${names[i]}" "$C_RESET"
  else
    printf '%s ' "$glyph"
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

declare -a COMPONENTS=()
declare -A COMPONENT_NAME=()
declare -A COMPONENT_DESC=()
declare -A COMPONENT_DEFAULT=()
declare -A COMPONENT_SCOPE=()   # "system" or "user"
declare -A COMPONENT_INSTALL=()
declare -A COMPONENT_CHECK=()

# register <key> <name> <desc> <default 0|1> <scope system|user> <install_fn> <check_fn>
register() {
  local key=$1 name=$2 desc=$3 default=$4 scope=$5 install_fn=$6 check_fn=$7
  COMPONENTS+=("$key")
  COMPONENT_NAME[$key]=$name
  COMPONENT_DESC[$key]=$desc
  COMPONENT_DEFAULT[$key]=$default
  COMPONENT_SCOPE[$key]=$scope
  COMPONENT_INSTALL[$key]=$install_fn
  COMPONENT_CHECK[$key]=$check_fn
}

# ════════════════════════════════════════════════════════════════════════════
# Components — see CLAUDE.md for the contract
# Each component: install_<key>, check_<key>, register line.
# ════════════════════════════════════════════════════════════════════════════

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
  apt-get update -y
  apt-get install -y \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
  usermod -aG docker "$USERNAME"
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
  if id -nG "$USERNAME" 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
    ok "$USERNAME in docker group"
  else
    ko "$USERNAME not in docker group"
  fi
}

register docker "Docker + Compose" "containers + compose plugin" 1 system install_docker check_docker

# ─── gh ────────────────────────────────────────────────────
install_gh() {
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg status=none
  chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
  local arch
  arch=$(dpkg --print-architecture)
  echo "deb [arch=$arch signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list
  apt-get update -y
  apt-get install -y gh
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

register gh "GitHub CLI" "gh" 1 system install_gh check_gh

# ─── node ──────────────────────────────────────────────────
install_node() {
  sudo -u "$USERNAME" -H bash <<EOF
set -eo pipefail
curl -fsSL -o- https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh | bash
export NVM_DIR="\$HOME/.nvm"
. "\$NVM_DIR/nvm.sh"
nvm install --lts
EOF
}

check_node() {
  local home
  home=$(getent passwd "$USERNAME" | cut -d: -f6)
  if [[ -d "$home/.nvm" ]]; then
    local v
    v=$(sudo -u "$USERNAME" -H bash -c '
      export NVM_DIR=$HOME/.nvm
      [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" 2>/dev/null
      command -v node >/dev/null && node --version
    ' 2>/dev/null)
    if [[ -n "$v" ]]; then
      ok "node $v (via nvm $NVM_VERSION)"
    else
      ko "node not available (nvm installed but node missing)"
    fi
  else
    ko "nvm not installed"
  fi
}

register node "Node LTS (via nvm)" "nvm + node LTS" 1 user install_node check_node

# ─── bun ───────────────────────────────────────────────────
install_bun() {
  sudo -u "$USERNAME" -H bash -c 'curl -fsSL https://bun.sh/install | bash'
}

check_bun() {
  local home
  home=$(getent passwd "$USERNAME" | cut -d: -f6)
  local v
  v=$(sudo -u "$USERNAME" -H bash -c '"$HOME/.bun/bin/bun" --version 2>/dev/null' 2>/dev/null || true)
  if [[ -n "$v" ]]; then
    ok "bun $v"
  else
    ko "bun not installed"
  fi
}

register bun "Bun" "JS runtime" 1 user install_bun check_bun

# ─── claude code ───────────────────────────────────────────
install_claude() {
  sudo -u "$USERNAME" -H bash <<'EOF'
set -eo pipefail
export NVM_DIR="$HOME/.nvm"
. "$NVM_DIR/nvm.sh"
npm install -g @anthropic-ai/claude-code
EOF
}

check_claude() {
  local v
  v=$(sudo -u "$USERNAME" -H bash -c '
    export NVM_DIR=$HOME/.nvm
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" 2>/dev/null
    command -v claude >/dev/null && echo yes
  ' 2>/dev/null || true)
  if [[ "$v" == "yes" ]]; then
    ok "claude code installed"
  else
    ko "claude code not installed"
  fi
}

register claude "Claude Code" "Anthropic's CLI" 1 user install_claude check_claude

# ════════════════════════════════════════════════════════════════════════════
# Baseline (mandatory, ordered) — NOT registered, always run
# ════════════════════════════════════════════════════════════════════════════

bl_update() {
  apt-get update -y
  apt-get upgrade -y
  apt-get install -y \
    wget gnupg lsb-release ca-certificates \
    software-properties-common ufw fail2ban git unzip curl
}

bl_timezone() {
  timedatectl set-timezone "$TIMEZONE"
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
  ufw allow 80/tcp  comment 'HTTP'
  ufw allow 443/tcp comment 'HTTPS'
  ufw --force enable
}

# set_sshd <key> <value> — patches sshd_config in place (idempotent)
set_sshd() {
  local k=$1 v=$2
  local cfg=/etc/ssh/sshd_config
  if grep -qE "^[#[:space:]]*${k}\b" "$cfg"; then
    sed -i -E "s|^[#[:space:]]*${k}.*|${k} ${v}|" "$cfg"
  else
    echo "${k} ${v}" >> "$cfg"
  fi
}

bl_ssh_harden() {
  local cfg=/etc/ssh/sshd_config
  cp "$cfg" "${cfg}.bak.$(date +%s)"
  set_sshd Port                   "$SSH_PORT"
  set_sshd PermitRootLogin        "no"
  set_sshd PasswordAuthentication "yes"   # flipped to no after key enrollment

  # Ubuntu 22.10+ uses ssh.socket activation, which overrides Port in sshd_config.
  if systemctl list-unit-files | grep -q '^ssh\.socket'; then
    systemctl disable --now ssh.socket 2>/dev/null || true
  fi

  sshd -t
  systemctl restart ssh
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
      sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
      sshd -t
      systemctl restart ssh
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
  body "vps-boot will create a sudo user, harden SSH, set up UFW + fail2ban,"
  body "and install your selected dev tools. Takes ~3 min on a fresh Ubuntu LTS."
  rail

  # ── username ──
  while :; do
    USERNAME=$(prompt_text "Username" "$arg_user")
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

  # ── port ──
  local port_default=${arg_port:-$(random_port)}
  while :; do
    SSH_PORT=$(prompt_text "SSH port" "$port_default")
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

  # ── password ──
  USER_PASSWORD=$(prompt_password "Password for $USERNAME")

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
      msel_args+=("${key}|${COMPONENT_NAME[$key]}|${COMPONENT_DESC[$key]}|${COMPONENT_DEFAULT[$key]}")
    done
    prompt_multiselect "Components" "${msel_args[@]}"
    enabled=("${PROMPT_MSEL_RESULT[@]}")
  else
    # QuickStart — all defaults
    local key
    for key in "${COMPONENTS[@]}"; do
      [[ "${COMPONENT_DEFAULT[$key]}" == "1" ]] && enabled+=("$key")
    done
  fi

  # ── confirm ──
  section "Confirm"
  body "${C_BOLD}user${C_RESET}      $USERNAME (sudo${enabled[*]+ · docker if selected})"
  body "${C_BOLD}ssh${C_RESET}       :$SSH_PORT, root login off, password auth temp on"
  body "${C_BOLD}firewall${C_RESET}  UFW — 22 closed · 80/443/$SSH_PORT open"
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
  body "${C_BOLD}timezone${C_RESET}  $TIMEZONE"
  rail

  local go
  prompt_radio "Continue?" go \
    "Continue|run the install" \
    "Abort|exit without changes"

  if [[ "$go" != "Continue" ]]; then
    die "Aborted by user."
  fi

  # ════════════════════════════════════════════════════════════════════
  # Run phase
  # ════════════════════════════════════════════════════════════════════
  section "Installing"

  export DEBIAN_FRONTEND=noninteractive

  step_run "System update"               bl_update
  step_run "Timezone → $TIMEZONE"        bl_timezone
  step_run "User $USERNAME"              bl_user
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
}

# ════════════════════════════════════════════════════════════════════════════
# cmd_check — verifier (also called inline at end of cmd_install)
# ════════════════════════════════════════════════════════════════════════════

cmd_check() {
  [[ $EUID -eq 0 ]] || die "Must run as root."
  USERNAME=${1:-}
  SSH_PORT=${2:-1986}
  [[ -n "$USERNAME" ]] || die "Usage: $0 check <username> [ssh_port]"
  id "$USERNAME" &>/dev/null || die "User '$USERNAME' does not exist."
  valid_port "$SSH_PORT" || die "Invalid SSH port: $SSH_PORT"

  banner
  if [[ -f "$STATE_FILE" ]]; then
    mapfile -t ENABLED_COMPONENTS < "$STATE_FILE"
    # filter out empty lines
    local -a filtered=()
    local k
    for k in "${ENABLED_COMPONENTS[@]}"; do
      [[ -n "$k" ]] && filtered+=("$k")
    done
    ENABLED_COMPONENTS=("${filtered[@]}")
  else
    # no state — check every registered component
    ENABLED_COMPONENTS=("${COMPONENTS[@]}")
  fi
  do_check
}

do_check() {
  PASS=0; FAIL=0; WARN=0

  section "Verify"

  # ── user ──
  if id -nG "$USERNAME" 2>/dev/null | tr ' ' '\n' | grep -qx sudo; then
    ok "$USERNAME in sudo group"
  else
    ko "$USERNAME not in sudo group"
  fi

  # ── timezone ──
  local tz
  tz=$(timedatectl show -p Timezone --value 2>/dev/null || true)
  if [[ "$tz" == "$TIMEZONE" ]]; then
    ok "timezone = $tz"
  else
    note "timezone = '$tz' (expected $TIMEZONE)"
  fi

  # ── ssh ──
  if ss -tlnH 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${SSH_PORT}\$"; then
    ok "sshd listening on $SSH_PORT"
  else
    ko "sshd not listening on $SSH_PORT"
  fi
  if ss -tlnH 2>/dev/null | awk '{print $4}' | grep -qE '[:.]22$'; then
    ko "something still listening on :22"
  else
    ok "port 22 closed"
  fi
  if grep -qE '^[[:space:]]*PermitRootLogin[[:space:]]+no\b' /etc/ssh/sshd_config; then
    ok "root login disabled"
  else
    ko "PermitRootLogin not 'no'"
  fi
  if systemctl is-active --quiet ssh.socket 2>/dev/null; then
    ko "ssh.socket still active (overrides sshd_config Port)"
  else
    ok "ssh.socket disabled"
  fi
  if sshd -t 2>/dev/null; then
    ok "sshd config valid"
  else
    ko "sshd config invalid"
  fi
  local pa
  pa=$(grep -E '^[[:space:]]*PasswordAuthentication[[:space:]]+' /etc/ssh/sshd_config | awk '{print $2}' | tail -1)
  if [[ "$pa" == "no" ]]; then
    ok "password auth disabled"
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
  local p
  for p in "$SSH_PORT" 80 443; do
    if ufw status 2>/dev/null | grep -qE "^${p}/tcp[[:space:]]+ALLOW"; then
      ok "$p/tcp allowed"
    else
      ko "$p/tcp not allowed"
    fi
  done

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
  body "${C_BOLD}Reconnect:${C_RESET}  ssh -p $SSH_PORT $USERNAME@$vps_ip"
  body "${C_BOLD}Re-verify:${C_RESET}  sudo $0 check $USERNAME $SSH_PORT"
  body "${C_DIM}Note: docker group membership requires a fresh login.${C_RESET}"
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
  install   Run the interactive wizard, harden the box, install tools.
            Args (optional) pre-fill the username and SSH port prompts.
  check     Re-run the verifier on an existing vps-boot install.
            Args required: username and SSH port to check.

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

main "$@"
