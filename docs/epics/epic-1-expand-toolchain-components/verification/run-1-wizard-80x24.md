# Run 1 — wizard rendering at 23 components on an 80×24 terminal

Host: fresh Ubuntu 24.04.4 LTS (`69.62.108.65`), driven through a tmux pane
created with `-x 80 -y 24` and `stty rows 24 cols 80` inside it. Every capture
below is `tmux capture-pane -p`, so the columns are the real ones.

The picker is never shown by the Full-install path the acceptance run takes, so
it was exercised separately by a harness that sources `vps-boot.sh` (sourcing
does not run `main`) and calls `prompt_multiselect` with the same arguments
`cmd_install` builds. That is a render check, not a second install — the host
was installed exactly once.

## Registry vs. applicable components

```
=== registry: 23 components ===
=== groups: core languages packaging agents cloud infra ===
=== term: 80x24 ===
=== applicable: 22 ===
```

Twenty-three components are registered. In **root-only** mode
`component_is_applicable` filters `sudo_nopasswd` out, so 22 are offered,
installed and checked. The twenty-third appears only in created-user mode. See
`../drift/09-root-mode-offers-22-of-23.md`.

## Picker — 12 lines for 22 items

```
◇  Components                                            22 selected · 0 skipped
│  ↑↓←→ move · space toggle · a all · n none · enter confirm
│
│  core      ›◉ CLI tools          ◉ Docker + Compose   ◉ GitHub CLI
│  languages  ◉ Node LTS           ◉ Python + pip       ◉ Go
│             ◉ Java (JDK)         ◉ Rust
│  packaging  ◉ Bun                ◉ pnpm               ◉ uv
│  agents     ◉ Claude Code        ◉ opencode           ◉ Codex
│             ◉ Gemini CLI         ◉ pi                 ◉ Hermes
│  cloud      ◉ Vercel CLI         ◉ Neon CLI           ◉ Hostinger CLI
│  infra      ◉ Caddy              ◉ herdr
```

Three columns, twelve printed lines, widest line 79 columns. `n` cleared every
box and updated the counter to `0 selected · 22 skipped`; `a` restored all 22;
`Down Down Right` moved the `›` cursor to Rust without corrupting the block.
Every redraw landed in place — no duplicated blocks, no lost rail.

## Collapse summary — 1 line, 79 columns

```
◇  Components                                            22 selected · 0 skipped
│  all 22  ·  core 3 · languages 5 · packaging 3 · agents 6 · cloud 3 · infra 2
```

## Install-mode radio — the continuation line carries the counts

```
◇  Install mode
│  (↑/↓ to move, enter to confirm)
│  ● Full install   everything — 22 tools
│              core 3 · languages 5 · packaging 3 · agents 6 · cloud 3 · infra 2
│  ○ Custom         pick what you need
```

## Confirm screen

**Before the fix in this PR** — the `install` line ran to 89 columns and wrapped,
and the wrapped remainder carried no rail prefix:

```
│  install   all 22  ·  core 3 · languages 5 · packaging 3 · agents 6 · cloud 3
· infra 2
```

`selection_summary` bounded only its *partial* branch; the full branch printed
`all N  ·  <every group count>` unconditionally. The Confirm screen's budget is
`term_cols - 13`, i.e. 67 at 80 columns, against a 76-character string.

**After** — the group counts truncate the same way any other list does:

```
◇  Confirm  ────────────────────────────────────────────────────────────
│  user      root (no sudo user)
│  ssh       :24617, root login on until key lockdown
│  firewall  UFW — only 24617/tcp open
│  install   all 22  ·  core 3 · languages 5 · packaging 3 · agents 6 · +2 more
│
```

The degradation ladder, printed against the real 23-key registry:

```
120 | all 23  ·  core 4 · languages 5 · packaging 3 · agents 6 · cloud 3 · infra 2
 80 | all 23  ·  core 4 · languages 5 · packaging 3 · agents 6 · cloud 3 · infra 2
 67 | all 23  ·  core 4 · languages 5 · packaging 3 · agents 6 · +2 more
 60 | all 23  ·  core 4 · languages 5 · packaging 3 · +3 more
 40 | all 23  ·  core 4 · +5 more
 12 | all 23
```

## Verdict

Picker, collapse summary and Confirm screen all render inside 80×24 at the full
registry size. That was true of the first two only; the Confirm screen needed
the `selection_summary` fix in this PR.

## Lines that still exceed 80 columns

Outside the three surfaces the acceptance criteria name, five fixed strings are
wider than 80 columns and wrap. None of them is count-dependent — they are the
same width at 12 components as at 23 — so they are pre-existing rather than
something this epic introduced, and they are recorded as a follow-up rather
than fixed here.

| Where | Columns |
|---|---|
| `enroll_ssh_key` — the Windows PowerShell one-liner | ~140 |
| `enroll_ssh_key` — `ok  lock down — disable password auth (key must already be on the server)` | 82 |
| `check_caddy` — `UFW denies 80/443 — run 'ufw allow …'` | 85 |
| `do_check` footer — the `vercel login --no-browser` sign-in hint | 98 |
| `do_check` footer — the `edit ~/.hostinger.yaml` sign-in hint | 91 |

The PowerShell line is a command meant to be copy-pasted whole, so wrapping it
is arguably correct; the other four are prose and should be bounded the way
`selection_summary` is.
