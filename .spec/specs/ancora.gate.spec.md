# Gate

`mix spec.check` orchestration: preflight hard failures, base resolution,
diff scoping, acknowledgment clearing, the two append-only guards,
change-scoped findings, and the never-silently-green guard. This subject
owns what the gate decides; `ancora.tasks` owns how it prints.

## Intent

A gate that can be configured into silence or that guesses a base is a gate
nobody can trust. Ancora's gate hard-fails when its environment cannot
produce a trustworthy answer (no base, no git, umbrella root), never falls
back silently, never executes anything but git, and keeps a small set of
guards whose narrowing is a recorded decision.

Modules: `Ancora.Gate`, `Ancora.Gate.Preflight`, `Ancora.AppendOnly`,
`Ancora.PolicyFiles`, `Ancora.ChangeAnalysis`.

```yaml spec-meta
id: ancora.gate
kind: workflow
status: active
summary: spec.check orchestration, hard-fail preflight, diff scoping, acknowledgment clearing, and the two append-only guards.
decisions:
  - ancora.decision.no_execution_no_state
  - ancora.decision.slimmed_governance
  - ancora.decision.cli_json_contract
  - ancora.decision.retirement_vocabulary
  - ancora.decision.durable_acknowledgments
```

## Requirements

```yaml spec-requirements
- id: ancora.gate.preflight_hard_fails
  statement: >-
    When the target has no `.spec/` corpus, the git executable is missing,
    the requested spec workspace cannot resolve its `specs/` directory, the
    target root is not inside a git repository, the base ref (explicit
    `--base` or the configured default) does not resolve, the git batch port
    exits or times out, a shallow boundary inside the requested `base..HEAD`
    range has at least one parent commit absent locally, or the target is an
    umbrella root, `mix spec.check` shall exit non-zero with
    verdict `result=fail tier=env` and a message naming the remedy. These
    conditions shall never be emitted as findings and shall not be
    configurable off. An unresolvable spec workspace shall name the directory
    that was checked and explain that `--spec-dir` selects the workspace, then
    end with the environment-tier verdict. No preflight check shall inspect `_build` or any
    `.app` file. Preflight shall load `.spec/config.yml` once and thread the
    resulting config through project identity and gate assembly. It shall pass
    the resolved `lib_paths` value, including nil, into project identity so
    that path does not read the config again. The config
    `lib_paths:` key shall override project identity only when present in
    `.spec/config.yml`; literal `elixirc_paths:` shall be honored otherwise.
    In `--json` mode, a preflight environment failure shall be returned as a
    version 1 JSON report with the fixed `ancora.tasks.json_report` shape, an
    empty `all_findings` list, and the error message before the failing
    environment-tier verdict. An unreadable working-tree source,
    test, or subject file shall also be an environment failure, while parse
    errors in readable files remain findings. A failed batch fetch shall close
    and poison its port so later fetches return `{:error, :port_poisoned}`.
    When a gate path reads a committed base blob without a batch port, it shall
    receive only the committed bytes; git warnings on stderr shall not enter
    the payload or produce a finding.
  priority: must
  stability: stable
- id: ancora.gate.default_base_no_fallback
  statement: >-
    When `--base` is absent the base shall be `git merge-base HEAD
    <default_base>` where `default_base` is the config key (default
    `origin/main`). There shall be no fallback to `main`, `master`, or `HEAD`
    when that ref is unresolvable; the missing-base message shall name all
    three remedies: `git fetch origin main`, `--base <ref>`, and the
    `default_base` config key. An explicit `--base HEAD` shall be accepted as
    an intentional empty diff.
  priority: must
  stability: stable
- id: ancora.gate.diff_scoped_versus_repo_state
  statement: >-
    `derived/drift`, `derived/growth`, `derived/shrink`,
    `derived/unresolved_calls`, `derived/unparseable_source`,
    `change/uncovered_file`, `change/missing_decision`,
    `tags/new_requirement_untagged`, `append/requirement_deleted`, and
    `append/must_downgraded` shall be computed only relative to the base and
    shall not fire for an empty diff. All other registry codes are repo-state
    and shall fire on every run while their condition holds.
  priority: must
  stability: stable
- id: ancora.gate.acknowledgment_clears
  statement: >-
    For a subject that Ancora.Derive.Ack reports as substantively changed in
    the diff, the gate shall suppress that subject's `derived/drift`,
    `derived/growth`, and `derived/shrink` findings. A `Spec-Ack:` trailer in
    the `base..HEAD` range shall downgrade the named code toward `info` or
    `warning` but never suppress it and never raise it. The durable
    acknowledgment record shall be `.spec/config.yml` through `severities:` or
    a per-subject override; trailers are a development convenience. When a
    finding resolves through a trailer that exists only in a non-tip commit,
    the gate shall warn on stderr that a squash merge will lose it only when
    removing that trailer would change the finding's resolved severity, and
    shall name `.spec/config.yml` as the promotion target. A legal trailer
    downgrade shall win over an equal or more severe config value while the
    trailer is present; after its removal, the config value shall apply.
  priority: must
  stability: stable
- id: ancora.gate.new_subject_self_clears
  statement: >-
    A subject whose spec file is added in the diff shall fire growth against
    an empty base set and clear in the same run, because the added
    requirement block is itself substantive; the gate shall need no special
    case for new subjects.
  priority: must
  stability: stable
- id: ancora.gate.two_append_guards
  statement: >-
    The gate shall enforce exactly two append-only guards, implemented
    by Ancora.AppendOnly: `append/requirement_deleted` when a requirement
    id present at base is absent on HEAD, and `append/must_downgraded`
    when a requirement's priority moves from `must` to `should`. An accepted
    ADR whose `affects:` names the exact requirement id shall authorize either
    change. For deletion only, `retires:` may instead name the exact
    requirement id or its subject id. A subject id in `affects:` shall not
    authorize either change, and `retires:` shall not authorize a downgrade.
    See `ancora.parsing.append_authorization_is_requirement_scoped` and
    `ancora.parsing.retirement_vocabulary` for the shared authorization rules.
    No other spec weakening shall be guarded.
  priority: must
  stability: stable
- id: ancora.gate.unanchored_subject
  statement: >-
    A subject whose HEAD derived set (bindings plus generated) is empty shall
    produce `derived/unanchored_subject` on every run until it is anchored or
    carries a per-subject override in config. The message shall name the
    per-subject override as the remedy for legitimate integration-only
    subjects.
  priority: must
  stability: stable
- id: ancora.gate.change_findings
  statement: >-
    A changed file under `lib_paths` that lies in no subject's footprint
    shall produce `change/uncovered_file`. A change to a governance file
    (the set Ancora.PolicyFiles defines: `.spec/specs/**`, `.spec/config.yml`,
    `.spec/AGENTS.md`, `.spec/README.md`) with no `.spec/decisions/` file
    added or changed in the same diff shall produce `change/missing_decision`.
  priority: must
  stability: evolving
- id: ancora.gate.strict_verdict
  statement: >-
    `mix spec.check` shall fail on any finding at `error` or `warning`
    severity and never on `info`. `mix spec.validate` shall fail on `error`
    and, with `--strict`, on `warning` too. A run with zero subjects shall be
    a true pass with a `subjects=0` summary.
  priority: must
  stability: stable
- id: ancora.gate.only_git_is_spawned
  statement: >-
    No ancora module except `Ancora.Git` shall spawn a subprocess or open a
    port; the gate shall never run tests, `mix`, or repository shell. This
    shall be enforced by a standing static test over `lib/` that fails on any
    `System.cmd`, `System.shell`, `Port.open`, or `:os.cmd` call outside
    `lib/ancora/git.ex` and `lib/ancora/git/`.
  priority: must
  stability: stable
- id: ancora.gate.no_derived_state
  statement: >-
    No task shall write derived state to the repository: there shall be no
    `state.json`, no hash baseline, and no `--output` flag on `spec.check` or
    `spec.validate`. Every gate input shall be the working tree plus git
    objects reachable from `--base`. The temporary base view shall contain
    only the configured spec directory, configured test paths, and project
    library paths, and the gate shall remove it after assembly returns or
    raises. During a gate run, the gate shall hold no per-run in-memory memo,
    registry, or ETS table; the run context it starts shall carry only the run
    root, base, and batch-port state, and stopping it shall leave no table or
    process behind. The temporary base-view root shall use
    `Ancora.TempName.cross_vm_suffix/0` and a non-recursive `File.mkdir/1`, so
    an already-present path fails instead of accepting a symlink.
  priority: must
  stability: stable
```

## Scenarios

```yaml spec-scenarios
- id: ancora.gate.scenario.missing_base_hard_fails
  given:
    - a tmp git repo with no `origin` remote and no `default_base` configured
  when:
    - `mix spec.check` runs with no `--base`
  then:
    - the exit status is non-zero
    - the last stdout line is `spec.check result=fail tier=env`
    - the message names `git fetch origin main`, `--base <ref>`, and `default_base`
  covers:
    - ancora.gate.preflight_hard_fails
    - ancora.gate.default_base_no_fallback
- id: ancora.gate.scenario.base_head_is_legal
  given:
    - a tmp git repo with a clean working tree
  when:
    - `mix spec.check --base HEAD` runs
  then:
    - no diff-scoped finding fires
    - the verdict reflects only repo-state findings
  covers:
    - ancora.gate.default_base_no_fallback
    - ancora.gate.diff_scoped_versus_repo_state
- id: ancora.gate.scenario.not_a_git_repo
  given:
    - a `--root` pointing at a directory with no `.git`
  when:
    - `mix spec.check` runs
  then:
    - the verdict is `result=fail tier=env`
    - no finding line is printed
  covers:
    - ancora.gate.preflight_hard_fails
- id: ancora.gate.scenario.missing_corpus
  given:
    - a git project whose root has no `.spec/` directory
  when:
    - `mix spec.check --base HEAD` runs
  then:
    - the message names `mix spec.init`
    - the last stdout line is `spec.check result=fail tier=env`
    - no exception is written to stderr
  covers:
    - ancora.gate.preflight_hard_fails
- id: ancora.gate.scenario.missing_git
  given:
    - a project with a corpus and no git executable on `PATH`
  when:
    - preflight or `Ancora.Git.BatchPort.open/1` runs
  then:
    - it returns an environment failure that names git and `PATH`
    - the batch port returns `{:error, :git_executable_not_found}` as data
    - no exception escapes from `Ancora.Git.run/3`
  covers:
    - ancora.gate.preflight_hard_fails
- id: ancora.gate.scenario.incomplete_shallow_range
  given:
    - a shallow clone with a boundary inside `base..HEAD` whose parent is absent locally
    - "a full clone of the same commit where a `Spec-Ack:` trailer makes the gate pass"
  when:
    - `mix spec.check` runs against the same base in both clones
  then:
    - the full clone passes
    - the shallow clone exits non-zero with verdict `result=fail tier=env`
    - "the message names `git fetch --unshallow` and `fetch-depth: 0`"
  covers:
    - ancora.gate.preflight_hard_fails
- id: ancora.gate.scenario.complete_shallow_range
  given:
    - a shallow repository with a boundary inside `base..HEAD`
    - every parent of that boundary is present locally
  when:
    - preflight runs
  then:
    - preflight accepts the range
  covers:
    - ancora.gate.preflight_hard_fails
- id: ancora.gate.scenario.poisoned_batch_port
  given:
    - a git batch fetch that times out
  when:
    - another fetch is attempted through the same port
  then:
    - the second fetch returns `{:error, :port_poisoned}`
    - no response from the timed out request is returned
  covers:
    - ancora.gate.preflight_hard_fails
- id: ancora.gate.scenario.unreadable_working_tree_input
  given:
    - a tagged test file or library source in the working tree cannot be read
  when:
    - `mix spec.check --base HEAD` runs
  then:
    - stdout names the unreadable file
    - the last stdout line is `spec.check result=fail tier=env errors=0 warnings=0`
    - no runtime exception escapes on stderr
  covers:
    - ancora.gate.preflight_hard_fails
- id: ancora.gate.scenario.json_target_read_failure
  given:
    - a target whose `mix.exs` has a non-literal `app:` value
  when:
    - `mix spec.check --json` runs
  then:
    - stdout contains one JSON report followed by the environment-tier verdict
    - the version 1 report has the fixed JSON shape, an empty `all_findings` list, and the target-read error
    - no plain error message appears on stdout
  covers:
    - ancora.gate.preflight_hard_fails
- id: ancora.gate.scenario.drift_cleared_by_spec_edit
  given:
    - a watched function body changed in the diff
    - one tagged call was added and another tagged call was removed
    - the subject's spec file has one requirement statement reworded in the same diff
  when:
    - the gate runs
  then:
    - no `derived/drift` fires for the subject
    - no `derived/growth` or `derived/shrink` fires for the subject
  covers:
    - ancora.gate.acknowledgment_clears
- id: ancora.gate.scenario.trailer_downgrades_not_silences
  given:
    - a drift finding for subject S
    - "a commit in `base..HEAD` with trailer `Spec-Ack: derived/drift=info`"
  when:
    - the gate runs
  then:
    - "the finding is present at severity `info` with `severity_source: :trailer`"
    - the verdict is `result=pass` if no other warning or error exists
  covers:
    - ancora.gate.acknowledgment_clears
- id: ancora.gate.scenario.trailer_never_raises
  given:
    - a drift finding configured at `info`
    - "a commit in `base..HEAD` with trailer `Spec-Ack: derived/drift=warning`"
  when:
    - the gate runs
  then:
    - "the finding remains at `info` with `severity_source: :config`"
    - the verdict is `result=pass` if no other warning or error exists
  covers:
    - ancora.gate.acknowledgment_clears
- id: ancora.gate.scenario.non_tip_trailer_warns_before_squash
  given:
    - a finding downgraded by a `Spec-Ack:` trailer below the branch tip
    - no trailer for that code on the tip commit
  when:
    - the gate runs before a squash merge
  then:
    - stderr names the applied code and severity
    - stderr says the acknowledgment will be lost by a squash merge
    - stderr names `.spec/config.yml` as the promotion target
    - a non-tip trailer that resolves no finding produces no loss warning
    - config at the trailer's severity makes the promoted branch silent
    - config more severe than the trailer keeps the loss warning because removing the trailer changes the resolved severity
    - after the trailer is removed, the config severity applies
  covers:
    - ancora.gate.acknowledgment_clears
- id: ancora.gate.scenario.new_subject_clears_itself
  given:
    - a new spec file and a new tagged test added in the same diff
  when:
    - the gate runs
  then:
    - no `derived/growth` fires for the new subject
  covers:
    - ancora.gate.new_subject_self_clears
- id: ancora.gate.scenario.deleted_requirement_without_adr
  given:
    - a requirement present at base and removed on HEAD
    - no accepted ADR names its exact id in `affects:` or names its exact id or subject in `retires:`
  when:
    - the gate runs
  then:
    - `append/requirement_deleted` fires at severity `error`
  covers:
    - ancora.gate.two_append_guards
- id: ancora.gate.scenario.subject_retirement_authorizes_deletion
  given:
    - a subject with multiple requirements at base
    - "an accepted ADR whose `retires:` names the subject id"
  when:
    - the subject is absent on HEAD
  then:
    - no `append/requirement_deleted` finding fires
  covers:
    - ancora.gate.two_append_guards
- id: ancora.gate.scenario.retirement_does_not_authorize_downgrade
  given:
    - "an accepted ADR whose `retires:` names a subject id but whose `affects:` does not name the requirement id"
  when:
    - a requirement in the subject moves from `must` to `should`
  then:
    - `append/must_downgraded` fires
  covers:
    - ancora.gate.two_append_guards
- id: ancora.gate.scenario.downgrade_authorized_by_adr
  given:
    - a requirement moved from `must` to `should` on HEAD
    - "an ADR with `status: accepted` whose `affects:` names the requirement id"
  when:
    - the gate runs
  then:
    - no `append/must_downgraded` fires
  covers:
    - ancora.gate.two_append_guards
- id: ancora.gate.scenario.unanchored_every_run
  given:
    - a subject whose tagged tests resolve to zero bindings
  when:
    - the gate runs twice on an unchanged tree
  then:
    - `derived/unanchored_subject` fires both times
    - the message mentions the `overrides:` config construct
  covers:
    - ancora.gate.unanchored_subject
- id: ancora.gate.scenario.override_silences_one_subject
  given:
    - two unanchored subjects A and B
    - config `overrides:` entry for A with code `derived/unanchored_subject`, severity `info`, and a reason
  when:
    - the gate runs
  then:
    - A's finding is `info`; B's finding is `warning`
  covers:
    - ancora.gate.unanchored_subject
- id: ancora.gate.scenario.uncovered_lib_file
  given:
    - a changed `lib/new_thing.ex` reached by no tagged test
  when:
    - the gate runs
  then:
    - `change/uncovered_file` fires naming `lib/new_thing.ex`
  covers:
    - ancora.gate.change_findings
- id: ancora.gate.scenario.governance_change_without_adr
  given:
    - `.spec/config.yml` changed in the diff and no file under `.spec/decisions/` changed
  when:
    - the gate runs
  then:
    - `change/missing_decision` fires
  covers:
    - ancora.gate.change_findings
- id: ancora.gate.scenario.warning_fails_check_not_validate
  given:
    - a corpus whose only finding is one warning
  when:
    - `mix spec.check`, `Ancora.validate/2`, and `mix spec.validate` run
  then:
    - spec.check exits non-zero with `result=fail`
    - "direct non-strict validation returns `fail: false` with one checked warning and no errors"
    - "direct strict validation returns `fail: true` with the same checked counts"
    - spec.validate exits zero with `result=pass`
    - spec.validate --strict exits non-zero
  covers:
    - ancora.gate.strict_verdict
- id: ancora.gate.scenario.empty_corpus_is_green
  given:
    - a git repo with an empty `.spec/specs/`
  when:
    - `mix spec.check --base HEAD` runs
  then:
    - the summary line reports `subjects=0`
    - the verdict is `result=pass`
  covers:
    - ancora.gate.strict_verdict
- id: ancora.gate.scenario.forbidden_spawner_test
  given:
    - a non-empty compile-time-rooted list of every file under `lib/` parsed to AST
    - the allowed git layer contains a known subprocess call
  when:
    - the static spawner test walks each AST
  then:
    - the detector finds the known call before applying the allowlist
    - no `System.cmd`, `System.shell`, `Port.open`, or `:os.cmd` call exists outside `lib/ancora/git.ex` and `lib/ancora/git/`
  covers:
    - ancora.gate.only_git_is_spawned
- id: ancora.gate.scenario.mix_tasks_load_only_dependencies
  given:
    - the package application module list contains exactly eight `spec.*` Mix tasks
  when:
    - the static task test reads each task's compiled attributes
  then:
    - every task declares exactly `deps.loadpaths` as its requirement
    - changing one task to a compiling requirement fails the test
  covers:
    - ancora.gate.only_git_is_spawned
- id: ancora.gate.scenario.no_output_flag_on_gate_tasks
  given:
    - `mix spec.check --output x.json`
  when:
    - the task parses its arguments
  then:
    - the run fails as a usage error
    - no file is written
  covers:
    - ancora.gate.no_derived_state
- id: ancora.gate.scenario.base_view_cleanup_on_resolver_raise
  given:
    - a gate run whose resolver membership callback raises during derivation
  when:
    - gate assembly exits through the resolver exception path
  then:
    - the exact temporary base-view directory returned by materialization no longer exists
  covers:
    - ancora.gate.no_derived_state
```

## Verification

```yaml spec-verification
- kind: tagged_tests
  covers:
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
```
