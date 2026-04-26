#!/usr/bin/env bash
# vps-bootstrap.sh — bare-minimum VPS setup (no Caddy, no Paperclip)
# Run as root on a fresh Ubuntu LTS VPS.
# Usage: sudo ./vps-bootstrap.sh <username> [ssh_port]   # ssh_port defaults to 1986

set -euo pipefail

# ─── Config ───────────────────────────────────────────────
USERNAME="${1:-}"
SSH_PORT="${2:-1986}"
TIMEZONE="Europe/Paris"
NVM_VERSION="v0.40.4"

# ─── Helpers ──────────────────────────────────────────────
log()  { printf '\n\033[1;36m[+] %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31m[✗] %s\033[0m\n' "$*" >&2; exit 1; }

# ─── Pre-flight ───────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Must run as root."
[[ -n "$USERNAME" ]] || die "Usage: $0 <username> [ssh_port]"
[[ "$SSH_PORT" =~ ^[0-9]+$ ]] && (( SSH_PORT >= 1 && SSH_PORT <= 65535 )) \
  || die "Invalid SSH port: '$SSH_PORT'"
id "$USERNAME" &>/dev/null && die "User '$USERNAME' already exists."

export DEBIAN_FRONTEND=noninteractive

# ─── System update ────────────────────────────────────────
log "Updating system…"
apt-get update -y
apt-get upgrade -y
apt-get install -y \
  wget gnupg lsb-release ca-certificates \
  software-properties-common ufw fail2ban git unzip

# ─── Timezone ─────────────────────────────────────────────
log "Setting timezone to $TIMEZONE…"
timedatectl set-timezone "$TIMEZONE"

# ─── User ─────────────────────────────────────────────────
log "Creating user '$USERNAME' (you'll be prompted for a password)…"
adduser --gecos "" "$USERNAME"
usermod -aG sudo "$USERNAME"

# ─── UFW (before SSH port change to avoid lockout) ────────
log "Configuring UFW…"
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSH_PORT"/tcp comment 'SSH'
ufw allow 80/tcp  comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw --force enable

# ─── SSH hardening ────────────────────────────────────────
log "Hardening SSH (port $SSH_PORT, no root login)…"
SSHD_CONFIG=/etc/ssh/sshd_config
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.$(date +%s)"

set_sshd() {
  local k="$1" v="$2"
  if grep -qE "^[#[:space:]]*${k}\b" "$SSHD_CONFIG"; then
    sed -i -E "s|^[#[:space:]]*${k}.*|${k} ${v}|" "$SSHD_CONFIG"
  else
    echo "${k} ${v}" >> "$SSHD_CONFIG"
  fi
}
set_sshd Port                   "$SSH_PORT"
set_sshd PermitRootLogin        "no"
set_sshd PasswordAuthentication "yes"   # flip to no after SSH key enrollment

# Ubuntu 22.10+ uses ssh.socket activation, which overrides Port in sshd_config.
# Kill the socket so the daemon's own Port directive is honored.
if systemctl list-unit-files | grep -q '^ssh\.socket'; then
  log "Disabling ssh.socket (socket activation overrides sshd_config Port)…"
  systemctl disable --now ssh.socket 2>/dev/null || true
fi

sshd -t || die "sshd config invalid — not restarting."

# ─── fail2ban ─────────────────────────────────────────────
log "Configuring fail2ban…"
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

log "Restarting ssh — after script ends, reconnect on port $SSH_PORT in a NEW terminal."
systemctl restart ssh

# ─── Docker (official repo) ───────────────────────────────
log "Installing Docker + Compose…"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y \
  docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
usermod -aG docker "$USERNAME"

# ─── GitHub CLI ───────────────────────────────────────────
log "Installing GitHub CLI…"
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg status=none
chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  > /etc/apt/sources.list.d/github-cli.list
apt-get update -y
apt-get install -y gh

# ─── User-scope toolchain ────────────────────────────────
# nvm, Node LTS, Bun, Claude Code
log "Installing user toolchain for '$USERNAME'…"
sudo -u "$USERNAME" -H bash <<EOF
set -euo pipefail

# nvm + Node LTS
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh | bash
export NVM_DIR="\$HOME/.nvm"
. "\$NVM_DIR/nvm.sh"
nvm install --lts
nvm use --lts

# Bun
curl -fsSL https://bun.sh/install | bash

# Claude Code
npm install -g @anthropic-ai/claude-code
EOF

# ─── Final step: enroll SSH key, then disable password auth ─
log "Bootstrap nearly complete — one interactive step left."

VPS_IP="$(hostname -I | awk '{print $1}')"
USER_HOME="$(getent passwd "$USERNAME" | cut -d: -f6)"
AUTH_KEYS="$USER_HOME/.ssh/authorized_keys"

cat <<EOF

──────────────────────────────────────────────────────────
Push your SSH public key from your laptop:

  Linux/macOS:
    ssh-copy-id -p $SSH_PORT $USERNAME@$VPS_IP

  Windows (PowerShell):
    type \$env:USERPROFILE\.ssh\id_ed25519.pub | ssh -p $SSH_PORT $USERNAME@$VPS_IP "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

VERIFY in a NEW terminal that key auth works:

  ssh -p $SSH_PORT -o PreferredAuthentications=publickey $USERNAME@$VPS_IP

Then come back here:
  - Type 'ok'   → script verifies the key and disables password auth
  - Type 'skip' → leave password auth on, handle it yourself later
──────────────────────────────────────────────────────────

EOF

while true; do
  read -r -p "> " response || { warn "stdin closed — skipping key enrollment."; exit 0; }
  case "$response" in
    ok|OK|yes|y)
      if [[ ! -s "$AUTH_KEYS" ]]; then
        warn "No key found at $AUTH_KEYS. Push it first, then try again."
        continue
      fi
      if ! ssh-keygen -l -f "$AUTH_KEYS" &>/dev/null; then
        warn "$AUTH_KEYS exists but contains no valid SSH key."
        continue
      fi
      # Belt-and-suspenders: fix perms in case key was pushed via an unusual method
      chown -R "$USERNAME:$USERNAME" "$USER_HOME/.ssh"
      chmod 700 "$USER_HOME/.ssh"
      chmod 600 "$AUTH_KEYS"
      log "Key valid. Disabling password auth…"
      sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' "$SSHD_CONFIG"
      sshd -t || die "sshd config invalid after lockdown."
      systemctl restart ssh
      log "Bootstrap complete. Password auth disabled — use your key from now on."
      log "Note: docker group membership requires a fresh login."
      exit 0
      ;;
    skip|SKIP|no|n)
      warn "Skipped. Password auth is still ON. Disable it manually:"
      warn "  sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config"
      warn "  sudo systemctl restart ssh"
      log "Note: docker group membership requires a fresh login."
      exit 0
      ;;
    *)
      echo "Type 'ok' or 'skip'."
      ;;
  esac
done