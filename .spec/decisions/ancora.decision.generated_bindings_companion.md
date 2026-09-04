---
id: ancora.decision.generated_bindings_companion
status: accepted
date: 2026-08-21
affects:
  - ancora.derive
  - ancora.derive.change_set_union
  - ancora.derive.base_reads_batched
  - ancora.derive.memo_is_run_scoped
  - ancora.derive.project_info_from_root
  - ancora.derive.membership_source_derived
  - ancora.derive.qualified_call_disposition
  - ancora.derive.unqualified_ladder
  - ancora.derive.dynamic_calls_unresolved
  - ancora.derive.resolver_is_pure
  - ancora.derive.imports_and_aliases
  - ancora.derive.parse_degrades_to_finding
  - ancora.derive.clause_extraction
  - ancora.derive.canonical_is_metadata_strip
  - ancora.derive.drift_scope_and_dedupe
  - ancora.derive.growth_and_shrink
  - ancora.derive.generated_bindings
  - ancora.derive.acknowledgment_is_substantive
  - ancora.derive.subject_footprint
  - ancora.derive.formatter_round_trip
---

# Generated Bindings: Companion `__using__/1` Bindings and the Transition Rule

## Context

A binding whose module is a member but which has no textual `def` on either
side is macro-generated. The first design classified every such binding as
generated and silent in comparison, because every Ecto app's tests call
`Repo.insert/1` and a standing finding there is noise. Red team showed the
silence also exempted project-owned `use`-injected API (a `MyApp.Schema`
macro injecting `changeset/2`) from drift entirely, and left the asymmetric
case (textual on one side, generated on the other) unenumerated.

## Decision

Three rules, applied in `Ancora.Derive.Compare`:

1. Generated binding whose module `use`s a member module: generated, and a
   companion binding `{injecting_module, :__using__, 1}` enters the subject's
   derived set. A behavioral edit to the macro's quoted body is then drift
   on every subject whose tests reach the injected API. The `use` forms are
   collected during the module's DefIndex parse.
2. Generated binding whose `use` target is outside membership
   (`Ecto.Repo`, `Phoenix.Controller`, and friends): generated, silent in
   comparison, counted in `spec.status` as dep-generated.
3. A binding textual on one side and generated or absent-textual on the
   other, with its module in membership and tests still calling it, is drift
   with the message "definition moved into or out of macro-generated code".

`spec.status` splits the `generated=` column into project-macro and dep
counts so the visibility lives where the silence is.

## Consequences

Positive: project macros are watched through their injector; dependency
facades stay quiet; the asymmetric case has one answer pinned by a dogfood
scenario.

Negative: a companion binding fires drift for any edit to `__using__/1`,
including edits to injected functions the subject's tests never call. That
over-approximation is accepted; the acknowledgment rule clears it with one
spec edit.
