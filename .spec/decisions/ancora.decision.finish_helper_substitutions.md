---
id: ancora.decision.finish_helper_substitutions
status: accepted
date: 2026-09-03
affects:
  - ancora.gate.preflight_hard_fails
  - ancora.gate.no_derived_state
  - ancora.tasks.verdict_grammar
  - ancora.tasks.stderr_pinning
  - ancora.tasks.json_report
  - ancora.tasks.prime_loop
  - ancora.derive.base_reads_batched
  - ancora.derive.project_info_from_root
  - ancora.review.view_model_builder
  - ancora.review.findings_delta_without_store
  - ancora.findings.modal_classifier
---

# Finish helper substitutions

## Context

Ancora had dedicated helpers for verdict decisions, JSON encoding, config
diagnostics, cross-VM temporary names, and status reports. Their production
callers still carried local copies or recomputed the same input. The review
artifact also retained root-reading entry points after its builder began
passing parsed base and HEAD data.

## Decision

Production callers use the existing helpers directly. Output and exit status
share `Ancora.Output.Verdict.pass?/1`; report JSON uses `Ancora.Json.encode!/1`;
and config diagnostics write through `Ancora.Output.config_diagnostic/1`.
Base views use `Ancora.TempName.cross_vm_suffix/0` and reject an existing root
path before writing. `BaseView.materialize/3` accepts a `:temp_root` option for
controlled collision checks and otherwise keeps its generated default. Prime
passes its status report to Next, and preflight passes its resolved library
paths to ProjectInfo. The obsolete root-reading review functions are removed.
ModalClass remains a standalone classifier and no longer claims the append-only
gate calls it.

## Consequences

The same values and report shapes reach callers through fewer implementations.
The base-view collision path now returns an error before a symlink can redirect
writes. No cache, registry, or process was added.
