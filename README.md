# vps-boot

> Resumable Ubuntu 26.04 amd64 hardening + dev toolchain. One command and an interactive wizard prepare a fresh VPS for root-only automation or an optional sudo user.

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
- **Hardened SSH** — UFW allows the selected SSH port plus 80/443 TCP when Caddy is selected; fail2ban protects SSH, and key enrollment finishes by disabling both password authentication methods.
- **Re-runnable lockdown** — `harden` redoes key enrollment and lockdown on its own, any time, as many times as you like, so an interrupted enrollment can be completed later.
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
| Firewall (UFW) | deny incoming; allow `<your-port>/tcp` plus 80/443 TCP when Caddy is selected; port 22 is rejected by the install wizard |
| SSH hardening | custom port, managed drop-in, and a timestamped backup of `sshd_config` |
| Recording install state | account and port to `/etc/vps-boot/config`, so `harden` and `check` need no arguments later |
| fail2ban | sshd jail; 1h ban; 5 retries in 10 minutes |

### Toolchain — 23 components, toggleable in Custom mode

Listed in registry order. Installation resolves prerequisites first (uv before Python, Node before npm tools). The groups are the six
`COMPONENT_GROUPS` values and the order the picker lays them out in.

| Group | Tool | What it is |
|---|---|---|
| core | Passwordless sudo | `NOPASSWD` sudo rule for a created user; not applicable to root-only installs |
| core | CLI tools | `jq`, `ripgrep`, `fd`, `htop`, `tree` |
| core | Docker + Compose | Docker CE, buildx, and the Compose plugin |
| core | GitHub CLI | `gh` |
| languages | Node LTS | current Node LTS via NodeSource |
| languages | Python + pip | stable Python 3 via uv, with pip in a separate development environment |
| languages | Go | latest Go from go.dev |
| languages | Java (JDK) | newest installable LTS OpenJDK, `JAVA_HOME` via `/etc/profile.d` |
| languages | Rust | `rustup` toolchain (rustc, cargo), installed system-wide; `RUSTUP_HOME`, `CARGO_HOME` (per-user cache) and `PATH` via `/etc/profile.d` |
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
| infra | Caddy | web server / reverse proxy via the official apt repo; installs and enables the service and opens **80/443 TCP** in UFW — `check` reports whether those ports remain allowed |
| infra | herdr | agent-aware terminal multiplexer |

Full install selects all default components. It includes Passwordless sudo only when you create a user, so it installs all 23 in that mode and 22 in root-only mode. With a created user, Custom shows Passwordless sudo in the same checkbox grid as the other components; root-only mode filters it out. The mode's label and its per-group counts are computed from the registry, so they never go stale — root-only reads `everything — 22 tools` over `core 3 · languages 5 · packaging 3 · agents 6 · cloud 3 · infra 2`.

Custom opens a grouped grid rather than a flat list — components sit under their group (`core`, `languages`, `packaging`, `agents`, `cloud`, `infra`) in up to three columns, which keeps the whole picker on an 80×24 screen. Move with `↑↓←→` (or `hjkl`), toggle with space, `a` ticks everything, `n` unticks everything, enter confirms. There is no separate "baseline only" mode: Custom then `n` is the two-keystroke equivalent. On a narrow terminal the grid drops to two columns, then one.

## Usage

### One-shot from a fresh root shell

```bash
curl -fsSL https://raw.githubusercontent.com/julienlegoux/vps-boot/main/vps-boot.sh | sudo bash -s install
```

**Run it under `tmux` or `screen`.** The install takes around 45 minutes and ends on a prompt that waits on you, so over SSH a dropped connection is expected rather than exceptional. If one does drop, [`harden`](#re-run-hardening) finishes the job.

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

APT operations wait up to three minutes for a background package manager to release its lock. The installer records progress before each step and then walks you through SSH key enrollment and prints verification and reconnect details. It applies final SSH lockdown only when you choose `ok` and a valid key exists. Choosing `skip`, or continuing with a missing or invalid key, leaves password authentication enabled.

### Locally, with the file already on the box

```bash
sudo ./vps-boot.sh install              # full wizard; root-only is the default
sudo ./vps-boot.sh install julien       # pre-fill username if you choose create
sudo ./vps-boot.sh install julien 2222  # pre-fill created username and SSH port
sudo ./vps-boot.sh --help
```

### Re-run hardening

Key enrollment and lockdown are their own command, idempotent and safe to run any number of times:

```bash
sudo ./vps-boot.sh harden           # account from /etc/vps-boot/config
sudo ./vps-boot.sh harden julien    # or name it explicitly
```

Remotely, when the install run lost its connection at the enrollment prompt:

```bash
curl -fsSL https://raw.githubusercontent.com/julienlegoux/vps-boot/main/vps-boot.sh | sudo bash -s harden
```

`install` records the account and port in `/etc/vps-boot/config` as soon as SSH hardening completes — before the enrollment prompt that can strand the run — so `harden` needs no arguments afterwards. It takes **no port argument** on purpose: it reads the port the host is already on (recorded state, then the managed drop-in, then `sshd -T`), because a mistyped port would move the listener off the one you are connected through.

It prints the same enrollment instructions as `install`, says so when the host is already locked down, and closes with either `Hardened — keys only` or `Pending — password auth is still on` plus the command to run again.

### Re-run verification

```bash
sudo ./vps-boot.sh check                    # account and port from /etc/vps-boot/config
sudo ./vps-boot.sh check root <port>        # root-only install
sudo ./vps-boot.sh check <username> <port>  # install with a created user
```

Arguments override the recorded account and port; without them the verifier reads `/etc/vps-boot/config`, falling back to `root` and port 1986 when there is no state file. It also reads `/etc/vps-boot/components` when present, so it checks only the components selected during installation.

An un-hardened host is reported as a warning rather than a failure — leaving password auth on can be a deliberate choice — and the warning names the `harden` command that closes it.

## After install — push your SSH key

The wizard pauses with copy-pasteable commands for Linux/macOS and Windows, filled with the selected account, VPS IP, and port. Verify the key in a new terminal before choosing `ok`.

Choosing `ok` requests lockdown, but lockdown proceeds only after `authorized_keys` exists and `ssh-keygen` confirms it contains a valid SSH key. Only then does vps-boot set `PasswordAuthentication no` and `KbdInteractiveAuthentication no`, validate the resulting sshd configuration, reload `ssh.service`, and—for a root-only install—change root to key-only access (`PermitRootLogin prohibit-password`). Created-user installs already have root login disabled. A missing or invalid key, or choosing `skip`, leaves password authentication enabled and the verifier reports a warning naming the `harden` command that fixes it.

None of this is a one-shot: [`harden`](#re-run-hardening) runs exactly the same enrollment and lockdown on its own, so a missed key, a `skip` you changed your mind about, or a connection that dropped at the prompt all recover the same way.

## Adding a component

The toolchain is a registry. Adding a new tool (for example, `btop`) requires an install function, a check function, and one `register` line in the Components section. See [`CLAUDE.md`](./.claude/CLAUDE.md) for the contract and a worked example.

## Resume an interrupted installation

```bash
sudo ./vps-boot.sh resume
sudo ./vps-boot.sh --version
```

The journal is stored under `/etc/vps-boot/journal`. It records intent, step status and verification output, including observed component versions. Passwords are never written there. If account creation was interrupted, the password is requested again to finish that step. `config` records SSH only after its configuration has been applied; `components` records the resolved selection before installation starts.

A fresh installation supports only Ubuntu **26.04 amd64 with systemd and OpenSSH already available**. SSH port 22 is rejected, including zero-padded input; 80 and 443 are also reserved when Caddy is selected. Root-only remains the default; creating a sudo user is optional.

Python is installed by uv under `/opt/vps-boot/python`. The `python` command executes a dedicated development venv with pip. Ubuntu's `python3` stays unchanged. Use project-specific virtual environments for dependencies. Rust's toolchain is shared, while Cargo caches live in each user's `~/.cargo`.

When Caddy is selected, installation opens **80/tcp and 443/tcp** in UFW. Caddy may already serve its default page before you configure an application. UDP 443 is not opened automatically. Docker-published ports can bypass UFW rules; bind private containers to loopback or configure Docker's forwarding policy explicitly. See [Docker's firewall limitations](https://docs.docker.com/engine/install/ubuntu/#firewall-limitations).

## Tests and CI

Woodpecker runs syntax checks, ShellCheck errors and the test suite inside Ubuntu 26.04 for pushes, pull requests, tags and manual runs. The repository is already enabled in Woodpecker.

```bash
docker build -t vps-boot-test:26.04 -f tests/Dockerfile .
docker run --rm -v "$PWD:/workspace:ro" vps-boot-test:26.04
woodpecker-cli lint .woodpecker/test.yaml
```

`tests/smoke_user.sh` exercises installed runtimes and CLI tools as an unprivileged test account. `tests/smoke_system.sh root` (or `user`) exercises SSH, UFW, nested Docker, Caddy and resume after an injected failure. The latter must only run in a **disposable privileged systemd container**, with no host Docker socket. These system tests are deliberately separate from ordinary unprivileged PR jobs.

Docker tests do not establish VPS boot, cloud-init or provider-firewall compatibility. See the [release verification record](docs/planning/release-0.1.0.md) for completed tests and remaining limits.

## Recovery

Locked yourself out? Open your provider's web-based root console. The installer backs up `/etc/ssh/sshd_config` before editing and writes its settings to `/etc/ssh/sshd_config.d/00-vps-boot.conf`. Restore the backup and remove or correct the managed drop-in, then run `sshd -t` before reloading `ssh.service`.

After recovery, re-apply the lockdown with `harden` and verify the matching setup with `check root <port>` for root-only or `check <username> <port>` for a created user.

If installation fails, the failed step includes the last 15 lines of `/var/log/vps-boot.log`. The script stops on the first failure. Reconnect and run `sudo ./vps-boot.sh resume` with this version of the script. It verifies successful steps and resumes interrupted or failed work with the latest available stable versions. It preserves the chosen account, port and components, including dependencies.

`install` refuses an existing installation. `resume` requires the new journal; older installations remain usable with `check` and `harden`, but cannot be inferred into a resumable installation. Neither command upgrades Ubuntu or adopts an unmanaged server.

## License

MIT.
