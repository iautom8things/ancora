---
id: ancora.decision.no_execution_no_state
status: accepted
date: 2026-08-21
affects:
  - ancora.gate
  - ancora.tasks
  - ancora.parsing
  - ancora.derive
  - ancora.scaffold
---

# No Execution, No Derived State, No Silent Fallback

## Context

specled_ex ran verification commands from the gate, cached coverage and
realization hashes in committed files, and fell back through four base
candidates when the configured one was missing. Each of those bought a
class of defects: repo-authored shell ran from a "read-only" task, baselines
drifted between branches and were regenerated to make conflicts go away,
and an unreachable `origin/main` produced a vacuous green. The ancora spec
names all three as charter constraints.

## Decision

- No ancora task executes tests or repository shell. The only subprocess is
  `git`, spawned from `Ancora.Git`. Export introspection of ancora's own
  dependencies in the tool VM is toolchain introspection, not project
  execution, and the load path never includes the target's `_build`.
- No derived state is written: no `state.json`, no hash baseline, no
  `--output` on gate tasks. `spec.review --output` writes a render target,
  which is not gate input. Every gate input is the working tree plus git
  objects reachable from `--base`.
- No silent base fallback. The default base is `merge-base HEAD
  <default_base>`; an unresolvable base is a `tier=env` hard failure naming
  the three remedies. `--base HEAD` is legal as an explicit empty diff.
- Warnings fail `spec.check`. A warning that cannot block is a report line,
  not a finding; repos that want softness set codes to `info` in the repo
  where review can see it.
- In `--json` mode, a preflight environment failure is a report with an empty
  `all_findings` list and the error message. The environment-tier verdict
  remains last, and no plain error line is written to stdout.
- `Ancora.Output` is the only stdout writer and `Output.Verdict.emit/2` the
  only `result=` producer; every gate path funnels through `gated/2`. The
  one verdict-less exit is an internal exception, and that absence is
  asserted by a golden test.

## Consequences

Positive: the gate is pure-source plus git, byte-identical across machines,
trustworthy when it is green, and honest when it cannot answer. Diff-scoped
findings need no baseline file to compare against.

Negative: per-run AST work is repeated on every invocation (measured in the
hundreds of milliseconds at fleet scale, with an on-disk OID cache recorded
as the re-entry option if the Atlas perf acceptance misses). Adopters with
no remote must learn `--base HEAD` or set `default_base` on day one; the
scaffold teaches both.
