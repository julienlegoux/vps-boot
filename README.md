# vps-boot

Single-script bootstrap for a fresh Ubuntu LTS VPS.

## Installs

- Non-root sudo user
- UFW (deny incoming, allow SSH + 80/443)
- fail2ban with sshd jail
- SSH on a custom port, root login disabled
- Docker CE + Compose
- GitHub CLI
- nvm + Node LTS
- Bun
- Claude Code

## Requirements

- Fresh Ubuntu
- Root access

## Usage

Two args: `username` (required), `ssh_port` (optional, defaults to `1986`).

```bash
curl -fsSL https://github.com/julienlegoux/vps-boot/blob/4ec328f74832b9b67f7007be785c102c16fe993e/vps-bootstrap.sh -o bootstrap.sh
sudo bash bootstrap.sh <username> <port>
```

Or locally:

```bash
sudo ./vps-bootstrap.sh <username> <port>
```

## After install

The script pauses at the end and prompts you to enroll your SSH key. From your laptop, push the key:

Linux/macOS:

```bash
ssh-copy-id -p <port> <username>@<vps-ip>
```

Windows (PowerShell):

```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh -p <port> <username>@<vps-ip> "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

Verify it works in a fresh terminal, then type `ok` at the script's prompt — password authentication is disabled automatically. Type `skip` to handle it yourself later.

`docker` group membership requires a fresh login to take effect.

## Recovery

Locked out? Use your provider's web-based root terminal. The script backs up `sshd_config` to `sshd_config.bak.<timestamp>` before editing.

## License

MIT.