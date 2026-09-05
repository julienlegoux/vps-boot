#!/usr/bin/env bash
# Only run inside a disposable Ubuntu 26.04 container with systemd and the
# privileges required by UFW and a nested Docker daemon. Never run on a host.
set -euo pipefail
[[ -f /.dockerenv && -d /run/systemd/system ]] || { echo 'Disposable systemd Docker container required' >&2; exit 1; }
cd /workspace
source ./vps-boot.sh
mode=${1:-root}
[[ $mode == root || $mode == user ]] || exit 1
USERNAME=root CREATE_USER=0 USER_PASSWORD="" SSH_PORT=2222
if [[ $mode == user ]]; then USERNAME=smokeuser CREATE_USER=1 USER_PASSWORD=temporary-container-only; fi
preflight
acquire_install_lock
enabled=(docker caddy)
initialize_journal
enroll_ssh_key() {
  local user_home
  user_home=$(getent passwd "$USERNAME" | cut -d: -f6)
  [[ -f /tmp/smoke-key ]] || ssh-keygen -q -t ed25519 -N '' -f /tmp/smoke-key
  install -d -m 0700 -o "$USERNAME" -g "$USERNAME" "$user_home/.ssh"
  install -m 0600 -o "$USERNAME" -g "$USERNAME" /tmp/smoke-key.pub "$user_home/.ssh/authorized_keys"
  lockdown_ssh
}
# Exercise an actual failed installation and then the public resume flow.
fail_once() { return 37; }
COMPONENT_INSTALL[caddy]=fail_once
set +e
( set -e; run_install )
rc=$?
set -e
[[ $rc == 37 && $(step_status caddy) == failed ]]
COMPONENT_INSTALL[caddy]=install_caddy
cmd_resume
[[ $(step_status docker) == succeeded && $(step_status caddy) == succeeded ]]
ssh -i /tmp/smoke-key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$SSH_PORT" "$USERNAME@127.0.0.1" true
docker run --rm hello-world
curl -fsS http://127.0.0.1/ >/dev/null
systemctl restart ssh.service caddy docker fail2ban
do_check
