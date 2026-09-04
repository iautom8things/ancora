---
id: ancora.decision.no_run_context_memo
status: accepted
date: 2026-09-03
affects:
  - ancora.derive
  - ancora.derive.memo_is_run_scoped
  - ancora.gate.no_derived_state
---

# Remove the unused RunContext memo

## Context

RunContext created a public ETS table for every detector run. Production code
never called `memo_put/4` or `memo_get/2`, so the table remained empty until
the run deleted it. Tests were the only callers. The gate now builds parsed AST
maps once per diff side and passes them through plain function arguments.

## Decision

Remove the ETS table, its kind-ranking rules, and the memo functions from
RunContext. RunContext retains the root, base, and batch port required for
batched git reads. Parse reuse remains plain data passed to comparison code.

## Consequences

Positive: each gate run allocates less state, and RunContext describes the only
resource it owns. The production path and its tests no longer imply a cache
that does not exist.

Negative: there is no in-process cache available for future parsing work. Any
new repeated work must first justify machinery beyond plain function arguments.
