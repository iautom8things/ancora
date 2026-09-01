# Changelog

All notable changes to this project are documented in this file.

## Unreleased

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
