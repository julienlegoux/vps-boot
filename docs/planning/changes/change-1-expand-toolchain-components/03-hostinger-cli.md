---
type: Decision
title: "Hostinger CLI"
description: "Is the Hostinger API CLI installable unattended on Ubuntu, and by which path?"
tags: [decision, change]
timestamp: 2026-08-16T09:05:00Z
phase: change
decision: 03
slug: hostinger-cli
status: decided
verdict: "A - GitHub releases tarball into /usr/local/bin, checksum-verified"
decided_via: triage
depends_on: [approach]
change: 1
change_slug: expand-toolchain-components
---

# Question

The user asked whether adding it is even possible. It is. `hostinger/api-cli` is
the official client, generated from the same OpenAPI spec as the API reference,
binary name `hostinger`, `hostinger version` prints the version.

What the upstream project does **not** offer, verified against both the GitHub
README and `docs.hostinger.com/api-reference/cli`:

- no apt repository and no `.deb`
- no `install.sh` one-liner
- no documented `go install`

The only two documented paths are Homebrew (`brew install
hostinger/tap/hostinger`) and a direct binary download from GitHub releases.
Release `v3.15.7` publishes `hostinger-<version>-linux-amd64.tar.gz`,
`-linux-arm64.tar.gz`, `-linux-386.tar.gz` plus a
`hostinger-<version>-checksums.sha256` file.

So this is the first component with no vendor-supplied installer — but it is not
a new pattern for the script: `install_go` (`vps-boot.sh:659-668`) already
resolves a version over HTTPS, maps `dpkg --print-architecture`, and pipes a
tarball into place. The archive naming here uses the same `amd64`/`arm64`
vocabulary `dpkg --print-architecture` emits, so the mapping is the identity.

Authentication: the CLI opens a browser sign-in by default and caches
credentials, which is useless on a headless box; the working path is the
`HOSTINGER_API_TOKEN` environment variable or `api_token:` in
`$HOME/.hostinger.yaml`, generated at hPanel → API. Note that a configured token
takes precedence over browser sign-in.

Relevant to whether this belongs here at all: the user runs a Hostinger VPS, so
a box provisioned by this script installing the CLI that manages that same
account is coherent — but it also means the token on the box can recreate or
destroy VPSes.

# Options

- **A. GitHub releases tarball into `/usr/local/bin`** — query
  `api.github.com/repos/hostinger/api-cli/releases/latest` for the tag, map the
  arch, download, verify against the published `checksums.sha256`, extract the
  `hostinger` binary. Mirrors `install_go`. Costs one unauthenticated GitHub API
  call per install (60/hour/IP limit — fine for a one-shot provisioner).
- **B. Same, but pin a version constant in the script** — no API call, fully
  reproducible, goes stale silently and there is no release process here to
  bump it.
- **C. Skip it** — the API is reachable with plain `curl` and a token; the CLI
  is a convenience.

# Recommendation

**A**, with the checksum step. It is the only path that tracks upstream without
a manual bump, and the script already owns an equivalent installer. Add
`hostinger version` to `check_hostinger`, and a sign-in hint naming
`HOSTINGER_API_TOKEN` rather than the browser flow, since the browser flow
cannot complete on this host.

Two things to carry into the epic's Notes: the checksum verification is not
optional here (unlike `go.dev`, this is a GitHub artifact download, and the
checksum file is published precisely for this), and the sign-in hint should say
plainly that the token is account-wide — the same credential that lists a VPS
can rebuild it.

# Verdict

**A.** Accepted at triage.

Resolve the latest tag from the GitHub releases API, map `dpkg
--print-architecture` onto the archive name, download, **verify against the
published `checksums.sha256`**, extract `hostinger` into `/usr/local/bin`.
Mirrors `install_go`. `check_hostinger` on `hostinger version`.

Sign-in hint names `HOSTINGER_API_TOKEN`, not the browser flow, which cannot
complete on this host — and states that the token is account-wide: the same
credential that lists a VPS can rebuild it.
