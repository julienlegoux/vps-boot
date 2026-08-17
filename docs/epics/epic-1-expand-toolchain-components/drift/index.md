# Drift — Epic 1: Expand the toolchain component registry

* [Root-only Full install offers 22 of the 23 registered components](./09-root-mode-offers-22-of-23.md) - accepted; `component_is_applicable` filters `sudo_nopasswd` out of root-only mode, so the epic's "all 23" criterion is 22 there
* [The documented user-scope idiom starts in a directory the user cannot read](./09-user-scope-idiom-inherits-root-cwd.md) - resolved (2026-08-17); `sudo -u … -H bash` inherits root's `/root` (mode 700) and the created-user run died on it, so the idiom now carries a mandatory `cd "$HOME"`
