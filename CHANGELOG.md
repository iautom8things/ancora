# Changelog

All notable changes to this project are documented in this file.

## Unreleased

## 1.0.0 - 2026-09-01

Final 1.0 release.

- Prevent derivation crashes when a variable named `quote` produces a nil AST
  child in real-world source.
- Read multi-expression `project/0` bodies statically when collecting project
  metadata.
- Emit a JSON report when preflight target reads fail in JSON mode.
- Repair the scripts-only replay harness selection and configuration. The M3
  replay validation ritual passed against real Atlas and Builder history at
  this tree.

## 1.0.0-rc.1 - 2026-09-01

First release candidate.

- Add source-derived traceability from tagged ExUnit tests to production
  functions, with growth, shrink, and drift findings across git revisions.
- Add `spec.init`, `spec.prime`, `spec.next`, `spec.status`, `spec.validate`,
  `spec.check`, and the self-contained `spec.review` HTML report.
- Enforce hard-fail environment checks, append-only requirements, spec tag
  coverage, governance co-changes, and a closed finding registry.
- Support human and JSON output through a single output layer with a stable
  verdict line.
