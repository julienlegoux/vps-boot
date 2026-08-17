# Change 1 — Expand the toolchain component registry

Take `vps-boot.sh` from twelve components to twenty-three: the Vercel CLI, the
Hostinger API CLI, the pi coding agent and a JDK as asked, plus the gaps an
audit of the existing registry turned up, plus Rust, the Neon CLI, Caddy and
automatic security updates. Rename QuickStart to Full install and rebuild the
component picker so twenty-three items still fit a terminal.

## Decisions

* [Approach](01-approach.md) - decided
* [Vercel CLI](02-vercel-cli.md) - decided
* [Hostinger CLI](03-hostinger-cli.md) - decided
* [pi coding agent](04-pi-coding-agent.md) - decided
* [Java / JDK](05-java-jdk.md) - decided
* [Shell essentials and build toolchain](06-shell-essentials.md) - decided
* [uv](07-uv.md) - decided
* [Additional agent CLIs](08-additional-agent-clis.md) - decided
* [Considered and excluded](09-considered-and-excluded.md) - na (confirmed, 4 repêchages)
* [Defaults and run order](10-defaults-and-run-order.md) - decided
* [Verification](11-verification.md) - decided
* [Scope boundary](12-scope-boundary.md) - decided
* [Acceptance criteria](13-acceptance-criteria.md) - decided
* [Install modes and component rendering](14-quickstart-scope.md) - decided
* [Test host](15-test-host.md) - decided
* [Rust](16-rust.md) - decided
* [Neon CLI](17-neon-cli.md) - decided
* [Caddy](18-caddy.md) - decided
* [Unattended upgrades](19-unattended-upgrades.md) - decided
* [Version audit](20-version-audit.md) - decided
