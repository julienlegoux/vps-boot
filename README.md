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
- **Batteries-included dev toolchain** — choose every default (Full install) or pick components from a grouped grid (Custom).
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

### Toolchain — 23 components, toggleable in Custom mode

Listed in registry order, which is also install order. The groups are the six
`COMPONENT_GROUPS` values and the order the picker lays them out in.

| Group | Tool | What it is |
|---|---|---|
| core | Passwordless sudo | `NOPASSWD` sudo rule for a created user; not applicable to root-only installs |
| core | CLI tools | `jq`, `ripgrep`, `fd`, `htop`, `tree` |
| core | Docker + Compose | Docker CE, buildx, and the Compose plugin |
| core | GitHub CLI | `gh` |
| languages | Node LTS | current Node LTS via NodeSource |
| languages | Python + pip | latest Python 3 via the deadsnakes PPA |
| languages | Go | latest Go from go.dev |
| languages | Java (JDK) | newest installable LTS OpenJDK, `JAVA_HOME` via `/etc/profile.d` |
| languages | Rust | `rustup` toolchain (rustc, cargo), installed system-wide; `RUSTUP_HOME`, `CARGO_HOME` and `PATH` via `/etc/profile.d` |
| packaging | Bun | JavaScript runtime |
| packaging | pnpm | fast npm-compatible package manager |
| packaging | uv | fast Python package/venv manager |
| agents | Claude Code | Anthropic's `claude` CLI |
| agents | opencode | open-source AI coding agent |
| agents | Codex | OpenAI's CLI coding agent |
| agents | Gemini CLI | Google's CLI coding agent |
| agents | pi | Earendil's CLI coding agent |
| agents | Hermes | NousResearch AI agent |
| cloud | Vercel CLI | `vercel` |
| cloud | Neon CLI | `neonctl` |
| cloud | Hostinger CLI | `hostinger` |
| infra | Caddy | web server / reverse proxy via the official apt repo; installs and enables the service but opens **no** firewall ports — `check` reports whether UFW allows 80/443 |
| infra | herdr | agent-aware terminal multiplexer |

Full install selects all default components. It includes Passwordless sudo only when you create a user, so it installs all 23 in that mode and 22 in root-only mode. With a created user, Custom shows Passwordless sudo in the same checkbox grid as the other components; root-only mode filters it out. The mode's label and its per-group counts are computed from the registry, so they never go stale — root-only reads `everything — 22 tools` over `core 3 · languages 5 · packaging 3 · agents 6 · cloud 3 · infra 2`.

Custom opens a grouped grid rather than a flat list — components sit under their group (`core`, `languages`, `packaging`, `agents`, `cloud`, `infra`) in up to three columns, which keeps the whole picker on an 80×24 screen. Move with `↑↓←→` (or `hjkl`), toggle with space, `a` ticks everything, `n` unticks everything, enter confirms. There is no separate "baseline only" mode: Custom then `n` is the two-keystroke equivalent. On a narrow terminal the grid drops to two columns, then one.

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
◇  Install mode    ● Full install   ○ Custom
◇  Components      (Custom only — grouped checkbox grid)
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
