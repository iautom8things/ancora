---
id: ancora.decision.field_friction_response
status: accepted
date: 2026-09-03
affects:
  - ancora.findings
  - ancora.gate
  - ancora.derive
  - ancora.tasks
  - ancora.scaffold
---

# Field Friction Response: Disclosure Codes, Model Unification, and the Ack End-State

## Context

One day of Atlas consumer sessions (2026-09-03) produced the full friction
ledger recorded on epic ancora-gg8: false greens the gate certified without
checking (borrowed tags, rewritten prose, trailer loss), false reds a correct
diff could not clear (path-set-only `change/missing_decision`, derived/drift
fan-out across 25 untouched subjects, a lib_paths trailing-slash mismatch),
one dropped capability consumers now hand-roll (forbidden-text tripwires),
subject-wide overrides forced onto single-requirement problems, and five
missed performance budgets. Four fresh-context investigations plus an
architecture pass, all recorded as comments on ancora-gg8, traced the ten
items to two diseases: the gate treats cooperative self-reports as evidence
and stays silent where they break down, and several findings compute their
trigger and their clearing rule from different models.

## Decision

Five principles govern the fixes; every change on the epic follows them.

1. Disclose, don't adjudicate. New codes make self-reports visible at info
   tier; nothing in the gate pretends static analysis validated semantics.
   Mutation-level judgment stays in the review tier.
2. The trigger rule and the clearing rule must share one model. Every new or
   changed finding names what clears it, and the clear is computed from the
   same inputs as the trigger.
3. Wire the authored fields before inventing grammar. `decisions:` frontmatter
   and `surface:` lists are already authored by consumers; the gate starts
   consulting them instead of growing new syntax.
4. Acks are tree-resident, scoped, and countable. Durable acknowledgment
   lives in `.spec/config.yml` overrides (scopable to a requirement), the
   `Spec-Ack:` trailer stays a dev-loop convenience per the ancora-sfu ruling,
   and every run's output counts what each suppression source hid.
5. Measure, then fix waste, then argue budgets, then (maybe) cache. The
   on-disk cache stays deferred; in-run waste fixes land first.

Concretely:

- The closed registry grows from 30 to 33 codes: `tags/tag_borrowed` (info,
  diff-scoped: a new test binds to a pre-existing requirement whose statement
  is untouched in the diff), `append/statement_changed` (info, diff-scoped: a
  requirement's statement text changed), and `derived/drift_transitive`
  (info, diff-scoped: drift on a binding whose defining file is outside the
  subject's declared `surface:`). All three are disclosures.
- `change/missing_decision` is suppressed for a changed subject spec whose
  `decisions:` frontmatter names an ADR that resolves in the index and whose
  `affects:` names the subject (or an id within it) back. Frontmatter-less
  governance files keep the co-change rule.
- Drift splits primary/transitive by the subject's `surface:` list; subjects
  without `surface:` keep the status quo (all drift primary).
- Override entries accept an optional `requirement:` key that narrows the
  match; entries without it behave exactly as today.
- Acknowledgment-suppressed derived findings are marked (severity info,
  `severity_source: :ack`) rather than destroyed; the default branch summary
  reports hidden info counts per source; `spec.check --explain-acks` lists
  only trailer- and ack-sourced findings. lib_paths are normalized once at
  ProjectInfo resolution.
- The command verification kind stays retired. The blessed successor for
  forbidden-text tripwires is the tagged ExUnit source-scan test, documented
  in docs/migration.md with a copyable template and backed by a small
  `Ancora.SourceScan` test-support helper that bakes in the vacuity guard and
  whole-token matching. The helper runs in the consumer's test suite, never
  in an ancora task, so no_execution_no_state is untouched.

Amendment to ancora.decision.slimmed_governance: that decision deliberately
left requirement statement rewrites unguarded, with reviewer attention as the
compensating control. `append/statement_changed` does not reopen it: an
info-tier disclosure blocks nothing and authorizes nothing; it hands the
reviewer the finite list of requirement ids whose text moved. The two-guard
set (`append/requirement_deleted`, `append/must_downgraded`) is unchanged and
remains the complete guard family.

Declined, with reasoning recorded on ancora-gg8: footprint-overlap scoring,
in-gate mutation sampling, semantic classification of statement edits,
binding-scoped ack grammar, per-binding drift aggregation, reinstating
`kind: command`, a declarative forbidden-pattern built-in, and durable
commit-metadata schemes.

## Consequences

Positive: the 46-error drift fan-out incident replays as 6 primary errors on
subjects that declared the changed file; a correct diff can clear
`missing_decision` without noise ADR edits; one blocked requirement no longer
mutes a 34-requirement subject; borrowed tags and prose rewrites become
visible in the diff where review happens; "what did this ack suppress" is a
one-flag question; the gate grows no new execution capability and no new ack
grammar.

Negative: three more registry codes to hold in the triage table; a standing
epic ADR authorizes repeat edits to its subjects while it stands, weakening
the one-decision-per-shift ideal; `surface:` lists become load-bearing for
drift severity, so a stale surface list misroutes drift to info until
corrected; info-tier disclosures are only as good as the reviewer reading
them.
