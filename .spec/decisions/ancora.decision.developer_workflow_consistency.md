---
id: ancora.decision.developer_workflow_consistency
status: accepted
date: 2026-09-07
affects:
  - ancora.derive
  - ancora.findings
  - ancora.gate
  - ancora.parsing
  - ancora.review
  - ancora.scaffold
  - ancora.tasks
---

# Keep developer guidance consistent with the gate

## Context

Next-step guidance asked for new subjects after ordinary README and test
edits, while missing governance decisions passed unnoticed. A selected
workspace could work in status but fail in check because preflight required
`.spec`. Nested Mix projects mixed repository-relative Git paths with
project-relative source paths, which could hide drift. Decision scaffolding
also let YAML coerce valid string ids into other scalar types.

## Decision

Next and check share the source-path and governance rules. Guidance preserves
the selected workspace in commands. Test-only edits proceed to check, where
binding changes receive their usual findings.

Each selected workspace supplies its own specs, decisions, and config.
Gate and review normalize its path before comparing Git objects, and reject
workspaces outside the project. Changes in nested projects use paths relative
to that project and exclude siblings. Review disables external diff drivers
and text conversion commands.

Invalid environment input returns an actionable error. Generated decision ids
remain strings through a parse round-trip. Setup docs explain the difference
between comparing with HEAD and comparing with the configured branch base.

## Consequences

Contributors receive the same governance advice from next and check. Custom
workspaces and nested projects use consistent file identities. Existing
classification labels, finding severities, and successful public API return
shapes remain unchanged.
