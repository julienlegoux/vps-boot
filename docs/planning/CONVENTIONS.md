---
type: Conventions
title: "vps-boot — Conventions"
description: "How this repo actually writes Bash: registry-driven components, UI helpers instead of echo, transactional writes, and Conventional Commits."
tags: [planning, conventions]
timestamp: 2026-08-16T07:28:00Z
status: final
mapped_commit: 2e2cb762a6c0e97fb8613ed4b4a331695b2fcd1d
mapped_at: 2026-08-16T07:28:00Z
---

# vps-boot — Conventions

## Naming & file layout

The repo is flat: `vps-boot.sh` at the root, `tests/test_vps_boot.sh`, `README.md`,
`LICENSE`, `.claude/CLAUDE.md`, and the `docs/planning/` bundle. There is no `src/`,
no module split, and no plan to introduce one — single-file distribution over
`curl | bash` is the point.

`.gitignore` is empty: `docs/` is tracked
([decision](/mapping/01-docs-directory-is-gitignored.md)), so nothing mechanically
keeps agent scratch out of the tree. A future scratch directory gets its own narrow
entry rather than a blanket `docs` exclusion.

Inside the script, order is meaningful and documented in `.claude/CLAUDE.md`:
constants, UI library, registry, components, baseline, enrollment, validation,
flows, entry point. New code goes in the section it belongs to rather than at the
end of the file.

Function names carry their role as a prefix:

| Prefix | Meaning | Example |
|---|---|---|
| `install_<key>` | component installer | `install_docker` |
| `check_<key>` | component verifier, called by `do_check` | `check_docker` |
| `bl_<step>` | mandatory baseline step | `bl_ssh_harden` |
| `cmd_<name>` | top-level command handler | `cmd_install` |
| `test_<case>` | test case | `test_root_lockdown_is_key_only` |

The three names of a component (`install_x`, `check_x`, `register x`) must agree —
that triple is the contract. Everything is `snake_case`: functions, locals, and
test names. Constants and script-level globals are `UPPER_SNAKE` and declared
`readonly` where they are not reassigned. Test-overridable constants take the form
`readonly NAME="${VPS_BOOT_NAME:-<default>}"`.

Components are separated by a box-drawing comment banner
(`# ─── docker ────…`), major sections by a full-width `# ═══…` rule.

## Code style

Bash with `set -euo pipefail`, two-space indent, `[[ ]]` over `[ ]` (a few `[ ]`
survive in `install_python` and `check_go`), `$( )` over backticks, and `local` on
every function-scoped variable. Long command invocations wrap with a trailing `\`.
There is no linter config — no `.shellcheckrc`, no `.editorconfig`, no formatter.
Style is maintained by hand and by matching surrounding code.

**Package manager: always `apt`, never `apt-get`**
([decision](/mapping/02-apt-vs-apt-get.md)). The rule holds throughout: commit
`ba7a29b` converted the last ten `apt-get` call sites and closed
[issue #16](https://github.com/julienlegoux/vps-boot/issues/16), so there is no
`apt-get` invocation left to copy from. `apt-cache search` (`vps-boot.sh:609`) is
the one deliberate exception — `apt search` is a different command with different
output, not a drop-in replacement.

**Never `echo`/`printf` for user-visible text.** Everything goes through the UI
helpers — `section`, `rail`, `body`, `step_run`, `ok`, `ko`, `note`, `die`, `warn`.
Raw `printf` appears only inside those helpers themselves and for inline prompt
validation messages. `install_*` bodies must not write to stdout at all: their
output is redirected to the log, and stray writes corrupt `step_run`'s line
rewriting.

**Every interactive read goes through `< /dev/tty`.** A bare `read` breaks the
`curl | sudo bash` path, where stdin is the script. Prompt helpers return values by
assigning to a caller-named output variable, never by echoing to stdout — so they
are called as `prompt_text "Label" VARNAME`, never as `$(prompt_text …)`.

**File writes are transactional**: `mktemp` a candidate beside the target, write,
`chmod`, validate, `mv -f` into place, and `rm -f` the candidate on every failure
branch. Where a validator exists (`visudo -cf`, `sshd -t`), it runs on the
candidate before the move, so a broken config can never replace a working one.

**Paths that tests need to redirect are constants with a `VPS_BOOT_*` override**,
not literals. `install_hermes` (`vps-boot.sh:687`, `:690`) hardcodes
`/etc/sudoers.d/99-vps-boot-hermes` and is the one exception; it is a deviation,
not the pattern.

**Comments explain why, not what.** The density is low but the comments that exist
carry non-obvious operational knowledge — why `/usr/bin/python3` is deliberately
left alone, why `ssh.socket` is masked, why orphan listeners are pkilled, why
`step_run` re-arms `errexit`. Preserve that habit: a workaround without its reason
will be "cleaned up" by the next reader.

## Testing

Tests live in `tests/test_vps_boot.sh` — one file, added to rather than split.
Adding a case means writing `test_<name>()` next to related cases and registering
it with a `run_test "<human label>" test_<name>` line in the block at the bottom;
a case that is not registered silently never runs.

Conventions the harness assumes:

- **Return codes, not assertion helpers.** A case returns 0 to pass. Multi-step
  cases chain `|| return 1`, with the final check as the bare last expression.
- **Labels are prose**, lowercase, describing behaviour rather than the function
  name: `"invalid sudoers leaves active rule unchanged"`.
- **Mock by redefining.** Shell functions and commands are shadowed inline
  (`chmod() { return 23; }`, stubbed `step_run` / `bl_*` / `do_check`). `run_test`
  runs each case in a subshell, so overrides are automatically scoped to it — do
  not add manual teardown.
- **Never touch real system paths.** Redirect via the `VPS_BOOT_*` exports into
  `$TEST_ROOT`. Shared fixture builders (`reset_real_sshd_fixture`,
  `prepare_stubbed_install_flow`, `write_previous_sshd_dropin`) exist to be reused.
- **Failure paths get first-class cases.** The dominant pattern is asserting that a
  failed operation restored the previous state — most SSH cases are of the form
  "X fails → previous drop-in restored".
- Behaviour promised in `README.md` is asserted against the README text
  (`test_readme_documents_new_defaults`), so user-facing changes update both.

Woodpecker runs `.woodpecker/test.yaml` on Ubuntu 26.04. Run `bash tests/test_vps_boot.sh` as root in the disposable Linux test container before pushing; the harness exits non-zero when any case fails. Real network/service acceptance is a separate privileged-container scenario.

## Error handling

`die "<msg>"` is reserved for unrecoverable preconditions — wrong UID, unknown
command, invalid argument, user abort. It prints to stderr and exits 1.

Inside `install_*` and `bl_*` functions, do not handle step failure: let
`set -euo pipefail` propagate it. `step_run` is the single place that catches it,
prints `✗`, and dumps the log tail. Explicit `return 1` is used only where a
failure needs cleanup first (removing a candidate file) or a diagnostic on stderr
before unwinding.

Diagnostics from inside a step go to **stderr** with an `ERROR: ` prefix
(`printf 'ERROR: effective SSH ports must be exactly: %s\n' … >&2`), since stdout
is reserved for the log.

`warn "<msg>"` is the non-fatal path — used where the run should continue in a
degraded state, as when key enrollment is skipped or `authorized_keys` fails to
parse.

In the verifier, the three outcomes are `ok` (pass), `ko` (fail — a real defect,
sets a non-zero exit) and `note` (warning — a deliberate, recoverable state such
as "password auth still enabled"). Choosing `ko` where `note` belongs turns an
operator's informed choice into a failed health check.

Cleanup that must survive an abort is armed with a trap **before** the operation it
cleans up (`vps-boot.sh:1259-1260`), never after.

## Commits & branches

**Conventional Commits**, lowercase subject, no trailing period:
`fix: create /run/sshd before validating sshd config`,
`feat: add pnpm and opencode components`,
`refactor: replace every apt-get call with apt`. `feat:`, `fix:`, `docs:`,
`refactor:` and `chore:` are all in use. Older history (pre-`731160a`) is plain sentence-case subjects — the
prefixed form is the current standard.

Subjects are imperative and specific about the change, not the area. Bodies are
usually omitted; the subject carries the meaning.

**Branches.** `main` is the stable install target; `develop` is the integration
trunk and the branch documented for bleeding-edge installs. Work branches are
`<agent-or-owner>/<topic>` — `claude/fix-fail2ban-ssh-error-RActb`,
`codex/reliable-bootstrap`. Both `main` and `develop` are published curl targets,
so a merge to either ships immediately.

**Merges, not rebases.** History shows merge commits throughout, via
`Merge pull request #N from …` for the GitHub PR flow and hand-written subjects for
direct integration merges (`Merge reliable bootstrap fixes into develop`).

Release markers are commits subjected `v0.0.1` / `v0.0.2` / `v0.0.3`. Release 0.1.0 introduces explicit script versioning; tag publication waits for acceptance validation.

## Review

No `CODEOWNERS`, no PR template, no required checks, no branch protection visible
in the repo. Review ceremony is the GitHub PR itself — the merge-commit history
shows PRs #3–#10 merged through the UI.

The practice visible in history is that a fix and the documentation of that fix are
separate adjacent commits (`fix: stop SSH lockdown after drop-in failure` followed
by `docs: record SSH failure review fix`).

`docs/` is tracked ([decision](/mapping/01-docs-directory-is-gitignored.md)), so
this planning bundle is a committed deliverable: it ships in a fresh clone, is
reviewed like any other change, and is available to downstream skills without being
regenerated. Keep it in sync in the same commit as the code it describes.

`.claude/CLAUDE.md` is the single canonical agent-instruction file
([decision](/mapping/03-agents-md-vs-claude-md.md)); the duplicate `AGENTS.md` was
deleted during this mapping. Changes to the component contract or the conventions
above update `.claude/CLAUDE.md` in the same commit.

## Release 0.1.0 refinements

`resume` uses an atomic, versioned journal; old state cannot be assumed complete.
New installs refuse existing state. Preserve the running SSH policy on retries.
Component dependencies are explicit and resolved before confirmation. Keep the
register display order independent from prerequisite execution order.

Use `report_version` or `version_value` for runtime probes. Capture command exit
status before parsing output and never report an unknown version as success.
Use per-user writable Cargo caches with the shared root-managed toolchain.
All shell scripts and YAML use LF on every checkout platform.

Do not kill apt services to acquire locks. Stop their timers, wait for active
transactions, and restore timers through the install cleanup path. Caddy opens
80/tcp and 443/tcp when selected; its description and confirmation must say so.
