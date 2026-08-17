---
type: Drift
title: "The documented user-scope idiom starts in a directory the user cannot read"
description: "SPECS.md and CLAUDE.md both showed `sudo -u \"$USERNAME\" -H bash` as the way to run a step as the created user, without the `cd \"$HOME\"` that makes it work — and the created-user acceptance run died on it."
tags: [epic-1, drift]
timestamp: 2026-08-17T02:00:00Z
epic: 1
issue: 09
---

# The documented user-scope idiom starts in a directory the user cannot read

- **Decided**: [`.claude/CLAUDE.md`](../../../../.claude/CLAUDE.md), *Conventions
  → Scope*: "For user-scope work inside an install fn, use:
  `sudo -u "$USERNAME" -H bash <<'EOF' / set -eo pipefail / … / EOF`", restated
  in [SPECS.md](../../../planning/SPECS.md) under *Architecture* as how `hermes`
  — the registry's only `user`-scope component — runs its installer.
- **Actual**: that idiom is incomplete, and the incompleteness is not cosmetic.
  `-H` sets `HOME`, but the working directory is inherited from the caller, and
  the caller is root sitting in `/root` at mode `700`. The user-scope shell
  therefore begins in a directory `$USERNAME` cannot stat, so anything the step
  runs that touches `.` fails. The created-user acceptance run died at Hermes,
  22 of 23 components in:

  ```
  error: failed to query metadata of symlink `/root/.venv`:
  Permission denied (os error 13)
  ```

  The upstream Hermes installer drives uv, and uv probes the working directory
  for `uv.toml` and `.venv` before it does anything else.
- **Because**: verified on the host, not inferred.
  `sudo stat -c '%a %U' /root` → `700 root`;
  `sudo bash -c 'cd /root && sudo -u devuser -H bash -c "ls -a ."'` →
  `ls: cannot access '.': Permission denied`; the same uv command run from
  `/root` fails with `failed to open file /root/uv.toml: Permission denied`
  and from `/home/devuser` succeeds. Root-only mode cannot expose this, because
  there `$USERNAME` *is* root — which is why the convention survived eight PRs
  and a clean root-only run 1, and why only the created-user run could find it.
- **Disposition**: resolved (2026-08-17) — the standard was wrong, so the
  standard changed rather than the code drifting away from it. Every user-scope
  body now begins `cd "$HOME" || exit 1`; `install_hermes`'s body moved into
  `hermes_user_script` so the suite can execute it against a stubbed installer
  and assert the resulting working directory, rather than grepping the source;
  `check_hermes` shells out the same way and got the same treatment. CLAUDE.md
  and SPECS.md now state the `cd` as mandatory, with the error text and the
  reason it is invisible in root-only mode. Recorded rather than fixed silently
  because the *documentation* is what produced the defect: a reader who trusted
  it would write the same bug into the next `user`-scope component.
- **Revisit when**: a second `user`-scope component is registered. One call site
  is a convention; two is a helper — `run_as_user()` wrapping the `sudo -u … -H`
  invocation with the `cd` built in would make the trap unwritable rather than
  merely documented.
- **Evidence**:
  [run-2-created-user-notes.md](../verification/run-2-created-user-notes.md),
  [run-2-created-user-install.txt](../verification/run-2-created-user-install.txt),
  PR #42
