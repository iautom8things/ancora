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
```

## Requirements

```yaml spec-requirements
- id: ancora.gate.preflight_hard_fails
  statement: >-
    When the target root is not inside a git repository, when the base ref
    (explicit `--base` or the configured default) does not resolve, or when
    the target is an umbrella root, `mix spec.check` shall exit non-zero with
    verdict `result=fail tier=env` and a message naming the remedy. These
    conditions shall never be emitted as findings and shall not be
    configurable off. No preflight check shall inspect `_build` or any
    `.app` file. Preflight shall load `.spec/config.yml` once and thread the
    resulting config through project identity and gate assembly. The config
    `lib_paths:` key shall override project identity only when present in
    `.spec/config.yml`; literal `elixirc_paths:` shall be honored otherwise.
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
    `warning` but never suppress it and never raise it.
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
    when a requirement's priority moves from `must` to `should`. Either
    is authorized, and the finding suppressed, only by an ADR with
    `status: accepted` whose `affects:` names the requirement id or its
    subject id. No other spec-weakening shall be guarded.
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
    objects reachable from `--base`.
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
- id: ancora.gate.scenario.drift_cleared_by_spec_edit
  given:
    - a watched function body changed in the diff
    - the subject's spec file has one requirement statement reworded in the same diff
  when:
    - the gate runs
  then:
    - no `derived/drift` fires for the subject
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
    - no ADR in the corpus names it or its subject
  when:
    - the gate runs
  then:
    - `append/requirement_deleted` fires at severity `error`
  covers:
    - ancora.gate.two_append_guards
- id: ancora.gate.scenario.downgrade_authorized_by_adr
  given:
    - a requirement moved from `must` to `should` on HEAD
    - "an ADR with `status: accepted` whose `affects:` names the subject id"
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
    - `mix spec.check` and `mix spec.validate` both run
  then:
    - spec.check exits non-zero with `result=fail`
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
    - every file under `lib/` parsed to AST
  when:
    - the static spawner test walks each AST
  then:
    - no `System.cmd`, `System.shell`, `Port.open`, or `:os.cmd` call exists outside `lib/ancora/git.ex` and `lib/ancora/git/`
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
