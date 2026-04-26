#!/usr/bin/env bash
# vps-check.sh — verify a vps-boot install is healthy
# Usage: sudo ./vps-check.sh <username> [ssh_port]

set -uo pipefail   # no -e: we want every check to run even when some fail

USERNAME="${1:-}"
SSH_PORT="${2:-1986}"

[[ -n "$USERNAME" ]] || { echo "Usage: $0 <username> [ssh_port]" >&2; exit 1; }
[[ $EUID -eq 0 ]]    || { echo "Run as root." >&2; exit 1; }
id "$USERNAME" &>/dev/null || { echo "User '$USERNAME' does not exist." >&2; exit 1; }

PASS=0; FAIL=0; WARN=0

ok()      { printf '  \033[1;32m✓\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
ko()      { printf '  \033[1;31m✗\033[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
note()    { printf '  \033[1;33m!\033[0m %s\n' "$*"; WARN=$((WARN+1)); }
section() { printf '\n\033[1;36m── %s ──\033[0m\n' "$*"; }

# ── User ─────────────────────────────────────────────────
section "User"
id -nG "$USERNAME" | tr ' ' '\n' | grep -qx sudo   && ok "in sudo group"   || ko "not in sudo group"
id -nG "$USERNAME" | tr ' ' '\n' | grep -qx docker && ok "in docker group" || ko "not in docker group"

# ── Timezone ─────────────────────────────────────────────
section "Timezone"
TZ_NOW=$(timedatectl show -p Timezone --value 2>/dev/null || true)
[[ "$TZ_NOW" == "Europe/Paris" ]] && ok "timezone = $TZ_NOW" || ko "timezone is '$TZ_NOW' (expected Europe/Paris)"

# ── SSH ──────────────────────────────────────────────────
section "SSH"
ss -tlnH 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${SSH_PORT}\$" \
  && ok "sshd listening on $SSH_PORT" || ko "sshd not listening on $SSH_PORT"

ss -tlnH 2>/dev/null | awk '{print $4}' | grep -qE '[:.]22$' \
  && ko "something still listening on :22" || ok "port 22 closed"

grep -qE '^[[:space:]]*PermitRootLogin[[:space:]]+no\b' /etc/ssh/sshd_config \
  && ok "root login disabled" || ko "PermitRootLogin not 'no'"

systemctl is-active --quiet ssh.socket \
  && ko "ssh.socket still active (overrides sshd_config Port)" \
  || ok "ssh.socket disabled"

sshd -t 2>/dev/null && ok "sshd config valid" || ko "sshd config invalid"

PASS_AUTH=$(grep -E '^[[:space:]]*PasswordAuthentication[[:space:]]+' /etc/ssh/sshd_config | awk '{print $2}' | tail -1)
[[ "$PASS_AUTH" == "no" ]] && ok "password auth disabled" || note "password auth still enabled"

USER_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)
AUTH_KEYS="$USER_HOME/.ssh/authorized_keys"
if [[ -s "$AUTH_KEYS" ]] && ssh-keygen -l -f "$AUTH_KEYS" &>/dev/null; then
  KCOUNT=$(ssh-keygen -l -f "$AUTH_KEYS" 2>/dev/null | wc -l)
  ok "$KCOUNT SSH key(s) enrolled for $USERNAME"
else
  note "no SSH keys enrolled for $USERNAME"
fi

# ── UFW ──────────────────────────────────────────────────
section "UFW"
ufw status 2>/dev/null | grep -q "Status: active" && ok "UFW active" || ko "UFW inactive"
for port in "$SSH_PORT" 80 443; do
  ufw status 2>/dev/null | grep -qE "^${port}/tcp[[:space:]]+ALLOW" \
    && ok "$port/tcp allowed" || ko "$port/tcp not allowed"
done

# ── fail2ban ─────────────────────────────────────────────
section "fail2ban"
systemctl is-active --quiet fail2ban && ok "fail2ban running" || ko "fail2ban not running"
fail2ban-client status sshd &>/dev/null && ok "sshd jail active" || ko "sshd jail not active"

# ── Docker ───────────────────────────────────────────────
section "Docker"
systemctl is-active --quiet docker && ok "docker daemon running" || ko "docker daemon not running"
command -v docker &>/dev/null \
  && ok "docker CLI: $(docker --version | awk '{print $3}' | tr -d ,)" \
  || ko "docker CLI missing"
docker compose version &>/dev/null \
  && ok "compose plugin: $(docker compose version --short 2>/dev/null)" \
  || ko "docker compose plugin missing"

# ── GitHub CLI ───────────────────────────────────────────
section "GitHub CLI"
command -v gh &>/dev/null \
  && ok "gh: $(gh --version | head -1 | awk '{print $3}')" \
  || ko "gh missing"

# ── User toolchain (run as $USERNAME) ────────────────────
section "User toolchain ($USERNAME)"
[[ -d "$USER_HOME/.nvm" ]] && ok "nvm installed" || ko "nvm not found"

NODE_V=$(sudo -u "$USERNAME" -H bash -c '
  export NVM_DIR=$HOME/.nvm
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" 2>/dev/null
  command -v node >/dev/null && node --version
' 2>/dev/null)
[[ -n "$NODE_V" ]] && ok "node $NODE_V" || ko "node not available"

BUN_V=$(sudo -u "$USERNAME" -H bash -c '"$HOME/.bun/bin/bun" --version 2>/dev/null' 2>/dev/null)
[[ -n "$BUN_V" ]] && ok "bun $BUN_V" || ko "bun not found"

CLAUDE_OK=$(sudo -u "$USERNAME" -H bash -c '
  export NVM_DIR=$HOME/.nvm
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" 2>/dev/null
  command -v claude >/dev/null && echo yes
' 2>/dev/null)
[[ "$CLAUDE_OK" == "yes" ]] && ok "claude code installed" || ko "claude code not found"

# ── Summary ──────────────────────────────────────────────
section "Summary"
printf "  %d passed, %d failed, %d warning(s)\n" "$PASS" "$FAIL" "$WARN"
[[ $FAIL -eq 0 ]] || exit 1
