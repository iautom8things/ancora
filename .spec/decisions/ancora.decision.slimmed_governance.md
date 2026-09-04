---
id: ancora.decision.slimmed_governance
status: accepted
date: 2026-08-21
affects:
  - ancora.gate
  - ancora.gate.preflight_hard_fails
  - ancora.gate.default_base_no_fallback
  - ancora.gate.diff_scoped_versus_repo_state
  - ancora.gate.acknowledgment_clears
  - ancora.gate.new_subject_self_clears
  - ancora.gate.two_append_guards
  - ancora.gate.unanchored_subject
  - ancora.gate.change_findings
  - ancora.gate.strict_verdict
  - ancora.gate.only_git_is_spawned
  - ancora.gate.no_derived_state
  - ancora.findings
  - ancora.findings.registry_closed
  - ancora.findings.registry_defaults
  - ancora.findings.messages_carry_remedy
  - ancora.findings.severity_precedence
  - ancora.findings.info_visibility
  - ancora.findings.trailer_grammar
  - ancora.findings.config_schema
  - ancora.findings.per_subject_overrides
  - ancora.findings.config_coversioned_note
---

# Slimmed Governance: Two Append-Only Guards

## Context

specled_ex grew twelve append-only guard codes, eight cross-field ADR rules,
and a baseline-dependent `no_baseline` condition. Most of them fired rarely,
several contradicted each other, and the maintenance cost fell on every
consuming repo's gate. The ancora spec settled on exactly two guards. This
ADR records, verbatim, what that narrowing stops guarding so the loss is a
decision and not an accident.

## Decision

The gate enforces `append/requirement_deleted` and `append/must_downgraded`
only. Authorization for either is an ADR with `status: accepted` whose
`affects:` names the exact requirement id. A subject id documents scope but
grants no append-only authorization. There is no weakening-class enum and no
`change_type` requirement.

The following are no longer guarded by any finding:

- scenario regression (a scenario removed or weakened)
- polarity change in a requirement statement
- a requirement disabled without a stated reason
- an ADR's `affects:` list widened after the fact
- same-PR self-authorization (the ADR and the weakening landing together)
- self-authorized weakening by the author of the requirement
- requirement statement rewrites that are neither deletion nor downgrade
- missing `change_type` on an ADR
- deletion of an ADR, including an unreferenced ADR that once authorized a
  weakening

Compensating controls: deleting an ADR that any surviving spec references
fires `spec/unknown_reference`; sole-committer PR review of `.spec/` diffs
covers the rest. `no_baseline` is not a finding because its condition
(no resolvable base) is now a `tier=env` hard failure.

The registry has 30 codes. The planning documents said 26; the enumerated
table after cutting `spec/prose_too_short` is 30. Adding a code is a change
to `ancora.findings` in this corpus.

The L13 dogfood activation rechecked this decision against
`Ancora.Finding`: the registry still has 30 codes, and the list above remains
the verbatim record of what the gate no longer guards.

## Consequences

Positive: the guard set fits in one moduledoc, consumer corpora migrate
without a standing backlog of governance findings, and the two surviving
guards have one authorization rule.

Negative: a reviewer who misses a scenario regression or a rewritten
statement has no mechanical backstop. Migration PRs must account for
reworded requirements clause by clause in the PR description, because the
gate no longer will.
