---
id: ancora.decision.cli_json_contract
status: accepted
date: 2026-09-03
affects:
  - ancora.gate.preflight_hard_fails
  - ancora.scaffold.init_writes_templates
  - ancora.scaffold.decision_new
  - ancora.scaffold.readme_commitments
  - ancora.tasks.gated_emission_paths
  - ancora.tasks.finding_line_format
  - ancora.tasks.json_report
  - ancora.tasks.report_task_flags
  - ancora.tasks.next_labels_verbatim
  - ancora.tasks.ci_explicit_base
  - ancora.parsing.stable_public_api
---

# CLI and JSON compatibility contract

## Context

Ancora 1.0.0 emitted different JSON keys for branch and environment failures,
and emitted no JSON for usage failures. A consumer could not read one report
shape across all outcomes. The published module documentation also exposed
internal modules without naming the library functions covered by semantic
versioning. CI relied on a local default-base setting, which made push checks
compare the branch against itself.

## Decision

The 1.0 series uses a version 1 JSON report with fixed top-level and nested
keys for ok, usage, environment, and branch outcomes. Missing data stays in
the report as null, an empty list, or zero. Consumers read the last stdout line
that parses as JSON, followed by the final verdict line.

The semver-stable library functions are `Ancora.Parser.parse_file/2`,
`Ancora.DecisionParser.parse_file/2`, `Ancora.check/2`, and
`Ancora.validate/2`. Every other callable module or function is internal. CI
passes its base explicitly, using the pull request base branch for pull
requests and the event's before SHA for pushes.

## Consequences

Existing JSON fields remain available, and consumers can use one decoder for
every exit tier. Adding the version and placeholder fields is an additive
1.0.1 change. Internal modules remain visible in generated documentation under
an Internal group but carry no compatibility promise. A branch-creation push
has no meaningful before SHA, so CI skips only that smoke step.
