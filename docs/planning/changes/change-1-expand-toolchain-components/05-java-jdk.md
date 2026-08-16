---
type: Decision
title: "Java / JDK"
description: "Which JDK distribution and version does the java component install, and does it set JAVA_HOME?"
tags: [decision, change]
timestamp: 2026-08-16T10:05:00Z
phase: change
decision: 05
slug: java-jdk
status: decided
verdict: "A-prime - probe for the newest installable LTS openjdk-NN-jdk-headless, plus JAVA_HOME via /etc/profile.d"
decided_via: discussion
depends_on: [approach]
change: 1
change_slug: expand-toolchain-components
---

# Question

Requested explicitly. Unlike the other three, Java is a *toolchain* addition
comparable to `go` or `python`, and it has four genuinely different install
paths with different upkeep profiles.

Facts:

- **Java 25 is the current LTS** (September 2025). Java 21 is the *previous*
  LTS and merely Ubuntu noble's chosen default — `default-jdk` resolves to
  `openjdk-21-jdk` on amd64. The two are not the same claim, and conflating them
  is what made the first version of this recommendation wrong.
- `openjdk-25-jdk-headless` **is packaged for noble**: version
  `25.0.3+9-2~24.04.2`, component `universe`, published in both the `updates`
  and `security` pockets. So the current LTS is reachable by plain `apt` with no
  third-party repository and with normal security updates. `universe` is enabled
  by default on Ubuntu Server images.
- `-headless` is the server variant — same `javac`, without the GUI/X11
  dependency chain.
- The existing language components pull the *newest* upstream rather than the
  distro version: `install_go` fetches whatever `go.dev/VERSION` reports,
  `install_python` probes deadsnakes for the newest installable `python3.X`. A
  distro-tracking Java would be the odd one out — but it is also the only one of
  the three whose distro package is a current LTS.
- `install_go` writes `/etc/profile.d/go.sh` to put its binaries on `PATH`. An
  apt JDK needs no `PATH` edit (`/usr/bin/java` is symlinked by
  `update-alternatives`), but many JVM tools — Gradle, Maven, some agents — read
  `JAVA_HOME`, which apt does **not** set.
- `install_python` carries a comment explaining why `/usr/bin/python3` is
  deliberately left alone. There is no equivalent hazard for Java: no distro
  service on this box runs on the JVM.

# Options

- **A. Probe for the newest installable `openjdk-NN-jdk-headless`** — iterate
  candidate versions descending, take the first that `apt install --dry-run`
  accepts. Lands on 25 today, follows the distro to 29 without an edit. This is
  precisely what `install_python` already does against deadsnakes
  (`vps-boot.sh:605-617`), so the idiom is in the file. **Superseded by A′ —
  see the Verdict: "newest" and "newest LTS" are not the same thing for Java.**
- **A′. Probe for the newest installable *LTS* `openjdk-NN-jdk-headless`** — the
  same descending probe, filtered to LTS majors only.
- **B. `openjdk-25-jdk-headless` pinned** — explicit, obvious, reproducible;
  goes stale silently when the next LTS lands and nobody bumps it (there is no
  release process here that would prompt a bump).
- **C. `default-jdk-headless`** — tracks Ubuntu's *default*, which is 21, i.e.
  one LTS behind. Simplest line, oldest Java.
- **D. Eclipse Temurin via the Adoptium apt repo** — also 25, but adds a
  third-party keyring and repo to maintain for a runtime that is API-identical
  to the OpenJDK build already in `universe`. Nothing to buy.
- **E. SDKMAN** — multi-version switching, but it is a `user`-scope shell
  function installer that writes to `~/.sdkman` and edits shell rc files;
  `hermes` is the only `user`-scope component and it needed a temporary sudoers
  rule to behave. Heavy for what is being asked.

# Recommendation

**A**, plus a `/etc/profile.d/java.sh` exporting `JAVA_HOME` derived at install
time from `readlink -f "$(command -v javac)"` — the same shape as
`install_go`'s profile drop-in, and the piece apt leaves out. Headless because
this is a server with no display, and the non-headless metapackage drags in X11
libraries for nothing.

Probing rather than pinning keeps Java consistent with how `go` and `python`
already behave in this script — newest available, resolved at install time, no
constant to forget. The difference is that Java's "newest available" comes from
Ubuntu's own archive rather than a third party, so it costs no extra repo.

**B is the honest fallback** if the probe loop reads as over-engineering for a
version that changes every two years: one explicit package name, and a note in
the epic that it needs revisiting at Java 29 (2027).

**D is out on the merits, not just on scope** — Temurin and the `universe`
OpenJDK build are the same upstream sources; the repo buys nothing here.

`check_java` reports `java -version` (which writes to **stderr** — the check must
redirect `2>&1`, a real trap here) and asserts `javac` exists, since a JRE-only
state would pass a naive `command -v java`.

# Verdict

**A′ — probe for the newest installable *LTS* JDK.** Reopened and re-decided
2026-08-16, after the epic was written; see the history below.

Probe descending via `apt install --dry-run`, the `install_python` idiom
(`vps-boot.sh:605-617`), but **restricted to LTS majors**. Since Java 17 the LTS
cadence is every four feature releases (two years): 17, 21, 25, 29, 33 — every
LTS major satisfies `(n - 21) % 4 == 0`. So the candidate filter is arithmetic
rather than a hardcoded list that would need bumping in 2027:

```bash
for (( n=CANDIDATE_MAX; n>=17; n-- )); do
  (( (n - 21) % 4 == 0 )) || continue          # LTS majors only
  apt install -y --dry-run "openjdk-${n}-jdk-headless" >/dev/null 2>&1 || continue
  jdk="openjdk-${n}-jdk-headless"; break
done
```

Lands on 25 today, picks up 29 when Ubuntu packages it, and can never select a
six-month feature release. Plus `/etc/profile.d/java.sh` exporting `JAVA_HOME`,
which apt does not set. `check_java` redirects `2>&1` (java writes its version
to stderr) and asserts `javac`, so a JRE-only state fails.

## History

**Second verdict — "newest installable", accepted at triage, now superseded.**
It had no notion of LTS: it took the highest `openjdk-NN` the archive would
install. Verified against noble today, that still resolves to 25 — but only
because Ubuntu has backported *only* LTS JDKs into noble (`17`, `21`, `25`
present; `22`, `23`, `24`, `26` absent). The correct answer was arriving by
accident, resting on an Ubuntu backport policy this project does not control,
and Ubuntu does package feature releases in its interim distros. A JDK with six
months of support on a box meant to be left running unattended is the wrong
default, and nothing in the probe would have prevented it.

**First recommendation — `default-jdk-headless`, wrong before triage.** It
conflated "Ubuntu's default" with "the current LTS": noble defaults to 21, the
current LTS is 25, and `openjdk-25-jdk-headless` is in noble's `universe`. That
correction is what prompted [20](20-version-audit.md).

Both misses share one root cause, worth stating because it is the thing to check
next time: **for Java, "default", "newest" and "newest LTS" are three different
versions.** For `go` and `python` — the components whose idiom was borrowed —
they collapse into one, which is why the idiom transplanted badly.
