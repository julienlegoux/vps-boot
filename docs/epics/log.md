# Log

## 2026-08-16

* **Epic 1 updated** after
  [decision 05](../planning/changes/change-1-expand-toolchain-components/05-java-jdk.md)
  was reopened: the `java` component probes for the newest installable **LTS**
  JDK (LTS majors only, `(n - 21) % 4 == 0`) rather than the newest JDK of any
  kind, which could have selected a six-month feature release. Scope table and
  Notes regenerated; issue #18 body updated; `gh_issue` and `milestone`
  unchanged.

* **Bundle established**: `docs/epics/` created by `define-change`.
* **Epic 1 created**: [Expand the toolchain component
  registry](epic-1-expand-toolchain-components/EPIC_1.md), from
  [change 1](../planning/changes/change-1-expand-toolchain-components/index.md)
  (20 decisions, all decided). Takes `vps-boot.sh` from twelve components to
  twenty-three, adds two baseline steps, and rebuilds the component picker.
