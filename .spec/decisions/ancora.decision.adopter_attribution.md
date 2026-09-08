---
id: ancora.decision.adopter_attribution
status: accepted
date: 2026-09-08
affects:
  - ancora.derive
  - ancora.parsing
  - ancora.findings
  - ancora.gate
  - ancora.review
  - ancora.scaffold
  - ancora.tasks

---

# Attribute observations to individual tagged tests

## Context

Whole-file call unions assign sibling tests and unused helpers to unrelated
subjects. Consumer agents then face findings that invite unrelated spec edits.
The investigation reproduced four wrong associations in a two-subject fixture,
order-dependent overrides, valid nested module failures and review severity
that disagreed with the gate. An empty surface silently demoted all drift.

## Decision

Derive from each tagged static carrier and applicable callbacks, following
reachable test helpers. Retain real shared setup observations and callsite
provenance. Share parsed sources and fragment results within a run. Never
execute the target or write derived gate input. Disclose incomplete dispatch
at existing unresolved-call severity and do not infer removal from uncertainty.

This amends the file-level and module-wide import behavior in the source-derived
membership and no-execution decisions for scoped carrier resolution. Production
membership and generated-binding companion rules remain unchanged.

Extend the field-friction ownership policy to binding additions and removals.
Surface is optional, nonempty and exact. Both declared sides retain ownership
for a simultaneous code change; first introduction is a visible policy choice.
Unknown paths remain primary. Declarations never establish tested coverage.

Reuse reasoned overrides for exact uncovered-file exceptions at info. Reject
ambiguous duplicate selectors and prefer requirement specificity over a subject
default. Use base coverage for deleted files, HEAD coverage otherwise.

Review reuses resolved HEAD findings and applies base config to base findings.
Severity changes are policy changes, not repaired defects. Resolve valid nested
__MODULE__ names throughout membership and extraction rather than skipping them.

## Consequences

Unrelated subjects no longer inherit a neighboring test's calls. Genuine shared
setup changes remain visible. Adopters need neither split test files nor write
cosmetic requirements. Two informational finding codes and exact file selectors
extend authored policy. Static analysis still cannot expand arbitrary macros or
prove semantic equivalence; its unresolved diagnostics retain that limitation.
