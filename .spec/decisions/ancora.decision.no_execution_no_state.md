---
id: ancora.decision.no_execution_no_state
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
  - ancora.tasks
  - ancora.tasks.exactly_eight
  - ancora.tasks.single_stdout_writer
  - ancora.tasks.verdict_grammar
  - ancora.tasks.gated_emission_paths
  - ancora.tasks.no_result_leak
  - ancora.tasks.stderr_pinning
  - ancora.tasks.finding_line_format
  - ancora.tasks.read_protocol_constant
  - ancora.tasks.check_flags
  - ancora.tasks.validate_flags
  - ancora.tasks.report_task_flags
  - ancora.tasks.next_labels_verbatim
  - ancora.tasks.status_derived_report
  - ancora.tasks.prime_loop
  - ancora.tasks.mix_bootstrap_posture
  - ancora.tasks.exit_codes
  - ancora.parsing
  - ancora.parsing.block_grammar_unchanged
  - ancora.parsing.retired_constructs_tolerated
  - ancora.parsing.structural_references
  - ancora.parsing.requirement_unverified
  - ancora.parsing.adr_grammar
  - ancora.parsing.tag_discovery
  - ancora.parsing.overlap_checks
  - ancora.parsing.stable_public_api
  - ancora.parsing.consumer_corpora_parse
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
  - ancora.scaffold
  - ancora.scaffold.init_writes_templates
  - ancora.scaffold.agents_md_content
  - ancora.scaffold.skill_md_content
  - ancora.scaffold.config_template
  - ancora.scaffold.no_retired_vocabulary
  - ancora.scaffold.fresh_adopter_round_trip
  - ancora.scaffold.decision_new
  - ancora.scaffold.readme_commitments
  - ancora.scaffold.migration_doc
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
  execution, and the load path never includes the target's `_build`. Static
  tests enumerate the package's eight Mix tasks and require each one to
  declare exactly `deps.loadpaths`. The subprocess and stdout guards also
  require a non-empty `lib/` candidate set and prove their detectors against
  known allowed calls before applying their allowlists.
- No derived state is written: no `state.json`, no hash baseline, no
  `--output` on gate tasks. `spec.review --output` writes a render target,
  which is not gate input. Every gate input is the working tree plus git
  objects reachable from `--base`.
- Repeated extraction work is removed with plain parsed-source maps built once
  per diff side and passed through the comparison call chain. Those maps are
  neither stored in a process nor retained after the gate returns.
- No silent base fallback. The default base is `merge-base HEAD
  <default_base>`; an unresolvable base is a `tier=env` hard failure naming
  the three remedies. `--base HEAD` is legal as an explicit empty diff.
- Warnings fail `spec.check`. A warning that cannot block is a report line,
  not a finding; repos that want softness set codes to `info` in the repo
  where review can see it.
- In `--json` mode, a preflight environment failure is a report with an empty
  `all_findings` list and the error message. The environment-tier verdict
  remains last, and no plain error line is written to stdout.
- Missing corpus, missing git, unreadable working-tree inputs, and failed git
  batch reads are environment failures represented as data. A failed batch
  fetch closes its port so no later request can consume stale bytes.
- `Ancora.Output` is the only stdout writer and `Output.Verdict.emit/2` the
  only `result=` producer; every gate path funnels through `gated/2`. The
  one verdict-less exit is an internal exception, and that absence is
  asserted by a golden test.

## Consequences

Positive: the gate is pure-source plus git, byte-identical across machines,
trustworthy when it is green, and honest when it cannot answer. Diff-scoped
findings need no baseline file to compare against.

Negative: AST work outside extraction still repeats within a gate run, and all
AST work repeats across separate invocations. The deferred on-disk OID cache
remains a possible re-entry after post-merge measurement. Adopters with no
remote must learn `--base HEAD` or set `default_base` on day one; the scaffold
teaches both.
