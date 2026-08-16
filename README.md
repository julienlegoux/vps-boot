# vps-boot

> Single-shot Ubuntu LTS hardening + dev toolchain. One command and an interactive wizard prepare a fresh VPS for root-only automation or an optional sudo user.

```bash
curl -fsSL https://raw.githubusercontent.com/julienlegoux/vps-boot/main/vps-boot.sh | sudo bash -s install
```

Prefer the bleeding edge? Swap `main` for `develop`:

```bash
curl -fsSL https://raw.githubusercontent.com/julienlegoux/vps-boot/develop/vps-boot.sh | sudo bash -s install
```

---

## Why

- **Root-only by default** — skip user creation for autonomous environments without sudo prompts, or create a non-root sudo user when you want one.
- **Hardened SSH** — UFW exposes only the selected SSH port, fail2ban protects it, and key enrollment finishes by disabling both password authentication methods.
- **Reliable package setup** — APT waits at most three minutes for background package locks instead of failing immediately during unattended upgrades.
- **Batteries-included dev toolchain** — choose every default (QuickStart) or select individual components (Custom).
- **Modular** — the wizard and verifier discover components from the same registry.

## What you get

### Baseline — applied in this order (user creation is optional)

| Step | Notes |
|---|---|
| System update | `apt update && upgrade` plus base packages, including `build-essential`; package locks wait up to 180 seconds |
| Automatic security updates | `unattended-upgrades` applies the security pocket only; `Automatic-Reboot` stays `false` |
| User | optional; skipped for the default root-only setup, otherwise creates a password-backed sudo user |
| Firewall (UFW) | deny incoming; allow only `<your-port>/tcp`; close the default SSH port `:22` unless you select port 22 |
| SSH hardening | custom port, managed drop-in, and a timestamped backup of `sshd_config` |
| fail2ban | sshd jail; 1h ban; 5 retries in 10 minutes |

### Toolchain — toggleable in Custom mode

| Tool | What it is |
|---|---|
| Passwordless sudo | `NOPASSWD` sudo rule for a created user; not applicable to root-only installs |
| Docker + Compose | Docker CE, buildx, and the Compose plugin |
| GitHub CLI | `gh` |
| Node LTS | current Node LTS via NodeSource |
| Bun | JavaScript runtime |
| pnpm | fast npm-compatible package manager |
| Claude Code | Anthropic's `claude` CLI |
| opencode | open-source AI coding agent |
| Python + pip | latest Python 3 via the deadsnakes PPA |
| Go | latest Go from go.dev |
| Hermes | NousResearch AI agent |
| herdr | agent-aware terminal multiplexer |

QuickStart selects all default components. It includes Passwordless sudo only when you create a user. With a created user, Custom shows Passwordless sudo in the same checkbox list as the other components; root-only mode filters it out.

## Usage

### One-shot from a fresh root shell

```bash
curl -fsSL https://raw.githubusercontent.com/julienlegoux/vps-boot/main/vps-boot.sh | sudo bash -s install
```

`User account` is the first prompt and defaults to `skip`. Username and password are requested only when you choose to create a user:

```text
◇  User account    ● skip — run everything as root   ○ create a sudo user
│  If create:
◇    Username      › julien
◇    Password      › ********
◇  SSH port        › 47829     (random, editable)
◇  Install mode    ● QuickStart   ○ Custom
◇  Components      (Custom only — checkbox list)
◇  Continue?       ● Continue     ○ Abort
```

APT operations wait up to three minutes for a background package manager to release its lock. The installer then walks you through SSH key enrollment and prints verification and reconnect details. It applies final SSH lockdown only when you choose `ok` and a valid key exists. Choosing `skip`, or continuing with a missing or invalid key, leaves password authentication enabled.

### Locally, with the file already on the box

```bash
sudo ./vps-boot.sh install              # full wizard; root-only is the default
sudo ./vps-boot.sh install julien       # pre-fill username if you choose create
sudo ./vps-boot.sh install julien 2222  # pre-fill created username and SSH port
sudo ./vps-boot.sh --help
```

### Re-run verification

Use the account and port selected during installation:

```bash
sudo ./vps-boot.sh check root <port>        # root-only install
sudo ./vps-boot.sh check <username> <port>  # install with a created user
```

The verifier reads `/etc/vps-boot/components` when present, so it checks only the components selected during installation.

## After install — push your SSH key

The wizard pauses with copy-pasteable commands for Linux/macOS and Windows, filled with the selected account, VPS IP, and port. Verify the key in a new terminal before choosing `ok`.

Choosing `ok` requests lockdown, but lockdown proceeds only after `authorized_keys` exists and `ssh-keygen` confirms it contains a valid SSH key. Only then does vps-boot set `PasswordAuthentication no` and `KbdInteractiveAuthentication no`, validate the resulting sshd configuration, reload `ssh.service`, and—for a root-only install—change root to key-only access (`PermitRootLogin prohibit-password`). Created-user installs already have root login disabled. A missing or invalid key, or choosing `skip`, leaves password authentication enabled and the verifier reports a warning.

## Adding a component

The toolchain is a registry. Adding a new tool (for example, `btop`) requires an install function, a check function, and one `register` line in the Components section. See [`CLAUDE.md`](./.claude/CLAUDE.md) for the contract and a worked example.

## Recovery

Locked yourself out? Open your provider's web-based root console. The installer backs up `/etc/ssh/sshd_config` before editing and writes its settings to `/etc/ssh/sshd_config.d/00-vps-boot.conf`. Restore the backup and remove or correct the managed drop-in, then run `sshd -t` before reloading `ssh.service`.

After recovery, verify the matching setup with `check root <port>` for root-only or `check <username> <port>` for a created user.

If installation fails, the failed step includes the last 15 lines of `/tmp/vps-boot.log`. The script stops on the first failure; fresh-server re-runs are not supported in this round, so rebuilding the VPS is usually the cleanest recovery.

## License

MIT.
