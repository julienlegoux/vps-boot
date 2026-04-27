# vps-boot

> Single-shot Ubuntu LTS hardening + dev toolchain. One command, an interactive wizard, and your fresh VPS is sudo-user'd, firewalled, fail2banned, and ready to ship code.

```bash
curl -fsSL https://raw.githubusercontent.com/julienlegoux/vps-boot/main/vps-boot.sh | sudo bash -s install
```

## Why

- **Hardened by default** — non-root sudo user, UFW with only the right ports open, fail2ban on SSH, root login disabled, custom SSH port, password auth disabled after key enrollment.
- **Batteries-included dev toolchain** — Docker + Compose, GitHub CLI, Node LTS via nvm, Bun, Claude Code. Pick all of them (QuickStart) or pick your own (Custom).
- **Modular** — one block per tool. Adding a new component is one `register` line + two functions, in one section. The wizard and the verifier pick it up automatically.
- **Verifies itself** — the install ends by running its own verifier as the "Done" screen. Re-runnable any time via `vps-boot.sh check`.

## What you get

### Baseline (always installed, in this order)

| Step              | Notes                                                            |
|-------------------|------------------------------------------------------------------|
| System update     | `apt update && upgrade` + base packages                          |
| User              | non-root, `sudo` group, password set non-interactively in wizard |
| Firewall (UFW)    | deny incoming · allow `<your-port>`/80/443 · default deny `:22`  |
| SSH hardening     | custom port, root login off, `sshd_config` backed up first       |
| fail2ban          | sshd jail · 1h ban · 5 retries / 10 min                          |

### Toolchain (toggleable in Custom mode)

| Tool              | What it is                          |
|-------------------|-------------------------------------|
| Docker + Compose  | Docker CE + buildx + compose plugin |
| GitHub CLI        | `gh`                                |
| Node LTS (via nvm)| `nvm` + Node LTS                    |
| Bun               | the Bun JS runtime                  |
| Claude Code       | Anthropic's `claude` CLI            |

## Usage

### One-shot from a fresh root shell

```bash
curl -fsSL https://raw.githubusercontent.com/julienlegoux/vps-boot/main/vps-boot.sh | sudo bash -s install
```

The wizard asks 4 things (or 5 in Custom mode):

```
◇  Username        › julien
◇  SSH port        › 47829     (random, editable)
◇  Password        › ********
◇  Install mode    ● QuickStart   ○ Custom
◇  Components      (Custom only — pick which tools)
◇  Confirm         ● Continue     ○ Abort
```

It runs, walks you through pushing your SSH key, locks down password auth, and prints a summary of what got installed and how to reconnect.

### Locally, with the file already on the box

```bash
sudo ./vps-boot.sh install              # full wizard
sudo ./vps-boot.sh install julien       # username pre-filled
sudo ./vps-boot.sh install julien 2222  # username + port pre-filled
sudo ./vps-boot.sh --help
```

### Re-run the verifier any time

```bash
sudo ./vps-boot.sh check julien 47829
```

Same output as the auto-check at the end of `install`, just standalone.

## After install — push your SSH key

The wizard pauses and shows you copy-pasteable one-liners for both Linux/macOS and Windows, pre-filled with your real user, IP, and port. Type `ok` to lock down password auth, or `skip` to keep it on and lock down later.

## Adding a component

The script's toolchain layer is a registry. Adding a new tool (e.g. `btop`) is three things in one section: an `install_btop` function, a `check_btop` function, and one `register` line. See [`CLAUDE.md`](./CLAUDE.md) for the contract and a worked example.

## Recovery

Locked yourself out? Use your provider's web-based root console. The script backs up `/etc/ssh/sshd_config` to `sshd_config.bak.<timestamp>` before editing, so a one-line `cp` restores the previous config.

If the wizard fails mid-install, the last 15 lines of `/tmp/vps-boot.log` are dumped under the failed step. The script aborts on first failure — no half-state recovery in this round, so on a fresh VPS you can usually rebuild the box and re-run.

## License

MIT.
