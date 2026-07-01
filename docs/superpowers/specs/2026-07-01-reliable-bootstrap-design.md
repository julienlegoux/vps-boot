# Reliable Bootstrap Design

## Goal

Make fresh Ubuntu LTS installs resilient to background package activity, make SSH lockdown reflect the running daemon's effective configuration, add passwordless sudo to QuickStart and Custom selection, and align the script with its documented optional-user/root-only flow.

## Branch and delivery model

- `main` remains unchanged.
- `develop` is rebuilt from `main`; the obsolete `claude/optional-user-creation-QWBGx` branch is removed.
- Work happens on `codex/reliable-bootstrap` based on the rebuilt `develop`.
- After implementation and verification, the feature branch is pushed, merged into `develop`, and `develop` is pushed.

## Package installation reliability

Every APT process started during the bootstrap must tolerate a fresh Ubuntu image's background `unattended-upgrades` process. The script will install a temporary APT configuration fragment that sets `DPkg::Lock::Timeout` to 180 seconds. A fragment is used instead of changing only direct `apt-get` calls so child installers such as NodeSource receive the same behavior. The fragment is removed when the install flow exits, whether it succeeds or fails.

`step_run` will execute each step in a subshell with `errexit` and `pipefail` active, capture its exit status outside Bash's conditional-command exception, and preserve the existing status-line/log-tail UI. A failed command inside an installer must stop that installer immediately; later commands must not obscure its exit status. This directly prevents Docker's failed package install from continuing into `usermod`.

The 180-second wait is a maximum. APT proceeds immediately when the lock becomes available.

## User-account modes

The wizard's first choice is `User account`:

- `skip` is the default and sets `USERNAME=root`; no user or password prompt is shown.
- `create` asks for a new username and password, creates the user, and adds it to the `sudo` group.

Docker group membership and user-scoped component checks branch on `USERNAME == root`. During a root-only install, SSH temporarily permits root password login so key enrollment remains possible. Successful key lockdown changes root access to key-only. During a created-user install, root SSH login is disabled.

## Passwordless sudo component

Passwordless sudo is a registered, default-on system component named `sudo_nopasswd` and appears in the existing Custom checkbox list for created-user installs. QuickStart selects it automatically. It is omitted from both selection modes for root-only installs because root already has unrestricted access.

The installer writes `/etc/sudoers.d/90-vps-boot-<username>` atomically with mode `0440` and this user-specific rule:

```sudoers
<username> ALL=(ALL:ALL) NOPASSWD: ALL
```

The candidate file is validated with `visudo -cf` before it replaces the destination. The verifier checks behavior with a non-interactive sudo invocation as the target user, rather than merely checking that a file exists.

The component key is persisted in `/etc/vps-boot/components` like every other selected component, so standalone checks only validate passwordless sudo when it was selected.

## SSH configuration and lockdown

The script will stop expanding commented and repeated directives in `/etc/ssh/sshd_config`. It will own a single early drop-in at `/etc/ssh/sshd_config.d/00-vps-boot.conf`, which wins over cloud-image fragments because OpenSSH uses the first value it obtains and expands included files in lexical order.

The owned drop-in contains the selected port and the current values for:

- `PermitRootLogin`
- `PasswordAuthentication`
- `KbdInteractiveAuthentication`

Before key enrollment, password and keyboard-interactive authentication are enabled so `ssh-copy-id` can work. After a non-empty, valid `authorized_keys` file is confirmed, the script fixes ownership and modes, changes both authentication settings to `no`, and changes root-only installs to `PermitRootLogin prohibit-password`. Created-user installs retain `PermitRootLogin no`.

Every SSH change is checked with `sshd -t`. The enrollment lockdown then reloads `ssh.service`, ensuring the running listener applies the new authentication policy without terminating the current session.

The verifier reads effective values from `sshd -T` instead of grepping one file. This detects cloud-init overrides and avoids reporting a secure state that the daemon is not actually using.

## Wizard and state flow

The Custom list is built after the user-account choice. When `USERNAME=root`, `sudo_nopasswd` is filtered out before rendering and before QuickStart defaults are collected. All other registered components keep their existing order and default behavior.

The confirmation screen states whether the install is root-only or creates a user, shows root-login behavior accurately, and includes Passwordless sudo in the selected component summary only when applicable.

## Error handling and recovery

- APT lock exhaustion fails the active step after 180 seconds and exposes APT's original error in `/tmp/vps-boot.log`.
- A malformed sudoers candidate never replaces the active file.
- An invalid SSH configuration is rejected before service reload.
- Missing or invalid SSH keys leave password authentication enabled and show the existing warning.
- The temporary APT timeout fragment is cleaned up by a top-level install-flow trap.

Re-running `install` with the same created username remains unsupported, consistent with the existing project contract. `check` remains non-mutating.

## Tests

A Bash regression suite will source the script without executing `main` and isolate filesystem/service commands with temporary paths or command stubs. It will cover:

1. `step_run` stops on the first failure and returns that status.
2. APT receives a 180-second lock timeout, including child APT processes through the temporary configuration fragment.
3. SSH configuration is emitted once in the owned drop-in and lockdown disables both password-capable methods.
4. Lockdown reloads `ssh.service` only after a valid configuration.
5. Effective SSH checks use `sshd -T` values.
6. Root-only mode skips user creation, password prompting, Docker group changes, and passwordless-sudo selection.
7. Created-user QuickStart enables passwordless sudo, while Custom can toggle it in the existing list.
8. The sudoers file has the expected rule and mode and is validated before installation.

The full suite will also run `bash -n`, ShellCheck when available, and README consistency checks.

## Documentation

README updates will describe:

- root-only as the default and created-user mode as an option;
- the three-minute maximum package-lock wait;
- Passwordless sudo as a QuickStart default and Custom checkbox;
- the SSH key enrollment transition from temporary password access to effective key-only access;
- the standalone `check` invocation for both `root` and created users.
