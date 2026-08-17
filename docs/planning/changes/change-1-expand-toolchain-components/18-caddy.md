---
type: Decision
title: "Caddy"
description: "Add Caddy — and decide what it does to the firewall the baseline just closed."
tags: [decision, change]
timestamp: 2026-08-16T09:05:00Z
phase: change
decision: 18
slug: caddy
status: decided
verdict: "A - install Caddy, open no ports; check_caddy emits a note when 80/443 are closed"
decided_via: triage
depends_on: [approach]
change: 1
change_slug: expand-toolchain-components
---

# Question

Pulled back in from [09-considered-and-excluded](09-considered-and-excluded.md)
at the user's request. The install itself is routine; the firewall interaction
is the actual decision, and it is the reason this was excluded in the first
place.

**Install** — official apt repo, same shape as `docker` and `gh`:

```
apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
  | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
  > /etc/apt/sources.list.d/caddy-stable.list
apt update && apt install -y caddy
```

**The conflict.** Installing the package *automatically starts and enables* a
`caddy` systemd service, and the shipped `/etc/caddy/Caddyfile` listens on `:80`.
Meanwhile `bl_ufw` sets deny-incoming and allows exactly one port —
`$SSH_PORT/tcp`. So out of the box the component produces a running web server
that nothing can reach, and `check_caddy` would report a green service behind a
closed door.

Worse, it is silent: `systemctl is-active caddy` says `active`, so a naive check
passes. The operator discovers it when a browser times out.

**The other half** is TLS. Caddy's headline feature is automatic HTTPS, which
requires port 443 reachable *and* a domain resolving to the box. This VPS is
addressed as `srv1796116.hstgr.cloud` / `69.62.108.65`; without a real domain,
Caddy cannot issue a certificate and falls back to serving plain HTTP. Opening
443 for a box with no domain buys exposure and no TLS.

This is why the exclusion doc argued the baseline owns network posture: `bl_ufw`
is a mandatory, non-registered step, and a component reaching into it inverts
the ordering the script is built on.

# Options

- **A. Install Caddy, open nothing.** The component installs and the service
  runs; the operator opens ports themselves when they have a domain. `check_caddy`
  emits a `note` (not a `ko`) stating that 80/443 are closed by UFW, so the
  situation is *visible* rather than silent.
- **B. Install Caddy and open 80/443 in the same component.** The box serves
  traffic immediately. It also silently widens the attack surface of a host
  whose whole selling point is that the baseline closed everything.
- **C. Install Caddy, and ask.** A wizard prompt — "open 80/443 for Caddy?" —
  making the exposure an explicit, recorded choice. Costs a prompt that only
  appears when the component is selected, which no component does today.
- **D. Install and stop/disable the service** until configured. Clean, but
  surprising: `apt install caddy` normally leaves a running server, and undoing
  that is the kind of cleverness that confuses the next reader.

# Recommendation

**A**, with the `note` in `check_caddy` doing the work.

The baseline's promise — one port open, everything else denied — is the most
valuable thing this script does, and a component that quietly punches two holes
in it costs more than the convenience it buys. Deferring the port opening to a
deliberate `ufw allow` is one command for the operator, at the moment they
actually have a domain pointed at the box and know which ports they want.

**C is the strong runner-up** and worth taking if the wizard is being touched
anyway for [14](14-quickstart-scope.md) — an explicit prompt is strictly better
than a footer note, because it forces the decision at install time instead of
hoping the operator reads the verifier output. Reject **B** outright: silent
firewall widening from a component is the one behaviour this codebase's baseline
exists to prevent.

Two riders for the epic: `check_caddy` must check both `systemctl is-active
caddy` **and** the UFW state for 80/443, otherwise it reports success on an
unreachable server. And the sign-in-hint slot should carry the follow-up —
`ufw allow 80,443/tcp` plus "point a domain at this box before expecting HTTPS".

# Verdict

**A.** Accepted at triage.

Caddy installs from its official apt repo (`dl.cloudsmith.io/public/caddy/stable`),
same keyring-plus-sources shape as `docker` and `gh`. **The component opens no
firewall ports.** The baseline's promise — one port open, everything else denied
— stays intact, and the operator runs `ufw allow` deliberately once a domain
points at the box.

`check_caddy` must check the UFW state for 80/443 **as well as**
`systemctl is-active caddy`, and emit a `note` (not a `ko`) when the service is
running behind a closed firewall. Without that the verifier reports green on an
unreachable server, which is the failure mode this decision exists to prevent.

Sign-in-hint slot carries the follow-up: `ufw allow 80,443/tcp`, and point a
domain at the box before expecting automatic HTTPS.

Option B — the component opening ports itself — rejected outright: silent
firewall widening is exactly what the baseline exists to prevent. Option C (a
wizard prompt) remains the better answer if the UI work in
[14](14-quickstart-scope.md) makes it cheap; revisit then.
