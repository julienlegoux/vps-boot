<div align="center">

# vps-boot

**From a fresh VPS to a ready-to-work dev environment.**

SSH hardening, development runtimes and AI agents — one script, your choice of tools.

`Ubuntu 26.04` · `amd64` · `Bash` · `MIT`

[Get started](#get-started) · [Tools](#tools) · [Commands](#commands) · [Recovery](#recovery)

</div>

---

## Get started

Start with a **fresh Ubuntu 26.04 amd64 VPS**, with systemd, OpenSSH and root access. Run inside `tmux` or `screen` to keep the session alive during installation.

```bash
curl -fsSL https://raw.githubusercontent.com/julienlegoux/vps-boot/main/vps-boot.sh | sudo bash -s install
```

The wizard guides you through four choices:

```text
◇  User account    skip — run as root / create a sudo user
◇  SSH port        random, editable
◇  Install mode    Full install / Custom
◇  Continue?       review and confirm
```

**Root-only is the default.** Create a user if you prefer a separate sudo account. SSH port 22 is rejected; ports 80 and 443 are reserved when Caddy is selected.

> **Trying the next release?** Replace `main` with `develop` in the command above. See the [release verification record](docs/planning/release-0.1.0.md) for tested behavior and remaining acceptance checks.

## What it takes care of

| Your server | Your workspace | Your next session |
|---|---|---|
| System updates and build tools | Choose the tools you need | Resume interrupted installations |
| UFW firewall and fail2ban | Dependencies installed automatically | Verify installed components |
| SSH key enrollment and lockdown | Stable Python, Node LTS and more | Finish SSH hardening later |
| Automatic security updates, no automatic reboot | Agent and cloud CLIs ready for sign-in | Keep the same account, port and selection |

APT waits up to **three minutes** for package locks. If a step fails, installation stops, prints the log tail and records progress for `resume`.

## Tools

**Full install** selects the whole catalogue: **23 components as root**, or **24 with a created user**. **Custom** lets you pick individual tools; prerequisites are added automatically.

| Group | Includes |
|---|---|
| Core | CLI utilities, Docker + Compose, GitHub CLI, optional passwordless sudo |
| Languages | Node, Python, Go, Java, Rust |
| Packaging | Bun, pnpm, uv |
| AI agents | Claude Code, opencode, Codex, Gemini CLI, pi, Hermes |
| Cloud | Vercel, Netlify, Neon, Hostinger |
| Infrastructure | Caddy, herdr |

<details>
<summary><strong>Explore the full catalogue</strong></summary>

### Toolchain — 24 components

| Group | Tool | Purpose |
|---|---|---|
| core | Passwordless sudo | Passwordless sudo for a created user |
| core | CLI tools | `jq`, `ripgrep`, `fd`, `htop`, `tree` |
| core | Docker + Compose | Docker CE, buildx and Compose |
| core | GitHub CLI | GitHub from the terminal |
| languages | Node LTS | Current Node LTS via NodeSource |
| languages | Python + pip | Stable Python via uv, with a dedicated pip environment |
| languages | Go | Latest Go toolchain |
| languages | Java (JDK) | Newest installable stable LTS OpenJDK |
| languages | Rust | Shared rustup toolchain, per-user Cargo caches |
| packaging | Bun | JavaScript runtime |
| packaging | pnpm | JavaScript package manager |
| packaging | uv | Python packages and virtual environments |
| agents | Claude Code | Anthropic coding agent |
| agents | opencode | Open-source coding agent |
| agents | Codex | OpenAI coding agent |
| agents | Gemini CLI | Google coding agent |
| agents | pi | Terminal coding agent |
| agents | Hermes | NousResearch AI agent |
| cloud | Vercel CLI | `vercel` |
| cloud | Netlify CLI | `netlify` — sign in with `netlify login` |
| cloud | Neon CLI | `neonctl` |
| cloud | Hostinger CLI | `hostinger` |
| infra | Caddy | Web server and reverse proxy |
| infra | herdr | Agent-aware terminal multiplexer |

Full install includes Passwordless sudo only when you create a user. In Custom, Passwordless sudo appears as a checkbox for that user.

Navigate with **arrow keys** or **hjkl**, toggle with **space**, select all with **a**, clear with **n**, and confirm with **Enter**. For the baseline alone, choose Custom and clear the selection.

</details>

## Commands

With a local copy of the script:

| Command | Use it to… |
|---|---|
| `sudo ./vps-boot.sh install` | Start the wizard on a fresh server |
| `sudo ./vps-boot.sh resume` | Continue interrupted or failed work |
| `sudo ./vps-boot.sh check` | Verify the recorded installation |
| `sudo ./vps-boot.sh harden` | Enroll a key and finish SSH lockdown |
| `sudo ./vps-boot.sh --help` | Show options |

**No local copy?** Use the same download command with the action you need:

```bash
curl -fsSL https://raw.githubusercontent.com/julienlegoux/vps-boot/main/vps-boot.sh | sudo bash -s resume
```

`resume` checks completed steps before skipping them and retries failed work. It requires a journal created by this version; legacy installations can still use `check` and `harden`.

<details>
<summary><strong>Account and port overrides</strong></summary>

```bash
sudo ./vps-boot.sh install julien 2222    # pre-fill the created account and port
sudo ./vps-boot.sh harden julien         # enroll keys for this account
sudo ./vps-boot.sh check root <port>     # verify a root-only setup
sudo ./vps-boot.sh check <username> <port>
```

Without overrides, `check` and `harden` read the account and port from `/etc/vps-boot/config`. `harden` takes no port argument: it uses the existing configuration.

</details>

## Finish with your SSH key

The wizard prints key-copy commands for **Linux, macOS and Windows**. Copy your key, then test it in a new terminal before confirming.

The installer applies final SSH lockdown only when you choose `ok` and a valid key exists. Choosing `skip`, or continuing with a missing or invalid key, leaves password authentication enabled. You can finish later:

```bash
curl -fsSL https://raw.githubusercontent.com/julienlegoux/vps-boot/main/vps-boot.sh | sudo bash -s harden
```

<details>
<summary><strong>What lockdown changes</strong></summary>

Lockdown proceeds only after `authorized_keys` contains a valid SSH key. Only then does the script set `PasswordAuthentication no` and `KbdInteractiveAuthentication no`, validate the SSH configuration and reload `ssh.service`. Root-only installations use key-only root access; installations with a created user disable root login.

Until lockdown is complete, `check` reports a warning and the command to finish it.

</details>

## Network access

UFW denies incoming traffic except on your selected SSH port. **Selecting Caddy also opens 80/443 TCP**; its default page may be available before you configure an application. UDP 443 is not opened automatically.

Docker-published ports can bypass UFW. Bind private services to loopback or configure Docker's forwarding policy. See [Docker's firewall limitations](https://docs.docker.com/engine/install/ubuntu/#firewall-limitations).

## Recovery

**Installation stopped?** Inspect the log, resolve the reported error, then run `resume` with this version of the script.

```bash
tail -n 60 /var/log/vps-boot.log
```

**Lost SSH access?** Use your provider's web console. Restore the SSH configuration backup and correct or remove `/etc/ssh/sshd_config.d/00-vps-boot.conf`. Run `sshd -t` before reloading `ssh.service`, then verify with `check`.

`install` refuses an existing installation. These commands do not upgrade Ubuntu or adopt an unmanaged server.

<details>
<summary><strong>State and runtime locations</strong></summary>

- `/etc/vps-boot/` stores the account, port, component selection and progress journal. Passwords are never recorded; an interrupted user-creation step requests the password again.
- `/opt/vps-boot/python` holds the uv-managed interpreter. `python` uses a dedicated development environment with pip; Ubuntu's `python3` stays unchanged. Use a virtual environment for each project.
- Rust's toolchain is shared; Cargo caches live in each user's `~/.cargo`.

</details>

## Development

Woodpecker runs Bash syntax checks, ShellCheck error checks and the regression suite on Ubuntu 26.04.

```bash
docker build -t vps-boot-test:26.04 -f tests/Dockerfile .
docker run --rm -v "$PWD:/workspace:ro" vps-boot-test:26.04
woodpecker-cli lint .woodpecker/test.yaml
```

[Adding a component](.claude/CLAUDE.md) · [Technical specs](docs/planning/SPECS.md) · [Release verification](docs/planning/release-0.1.0.md)

<details>
<summary><strong>Service acceptance tests</strong></summary>

`tests/smoke_user.sh` checks installed runtimes and CLIs as an unprivileged account. `tests/smoke_system.sh root` (or `user`) covers SSH, UFW, nested Docker, Caddy and resume after an injected failure.

Run the system scenarios only in a **disposable privileged systemd container**, without the host Docker socket. They are separate from ordinary PR jobs. Docker tests do not establish VPS boot, cloud-init or provider-firewall compatibility.

</details>

---

Licensed under **MIT**.
