# Task Surface and Output Contract

The eight `mix spec.*` tasks, their flags and output states, the single
stdout writer, the verdict grammar, and one scenario per emission path.

## Intent

The verdict line is the contract agents and CI read. In specled_ex it was
lost on several emission paths, each discovered in production. Ancora makes
it structural: one module writes stdout, one function produces `result=`,
every gate path funnels through one wrapper, and the only verdict-less exit
is an internal exception. This subject pins that per path so the gate itself
governs its own output discipline.

Modules: `Ancora.Output`, `Ancora.Output.Verdict`, `Ancora.Prime`,
`Ancora.Next`, `Ancora.Status`, `Ancora.Json`, `Ancora.TaskArgs`,
`Mix.Tasks.Spec.{Prime,Next,Check,Status,Review,Init,Validate,Decision.New}`.

```yaml spec-meta
id: ancora.tasks
kind: module
status: active
summary: The eight spec.* tasks, single-writer stdout, verdict grammar, and per-emission-path output contract.
decisions:
  - ancora.decision.no_execution_no_state
  - ancora.decision.field_friction_response
  - ancora.decision.cli_json_contract
```

## Requirements

```yaml spec-requirements
- id: ancora.tasks.exactly_eight
  statement: >-
    The package shall define exactly eight Mix tasks: `spec.prime`,
    `spec.next`, `spec.check`, `spec.status`, `spec.review`, `spec.init`,
    `spec.validate`, and `spec.decision.new`. No task under any other name
    shall exist.
  priority: must
  stability: stable
- id: ancora.tasks.single_stdout_writer
  statement: >-
    Ancora.Output and Ancora.Output.Verdict shall be the only modules that
    write to stdout. A standing static test shall parse every file under
    `lib/` and fail on any call to `IO.puts`, `IO.write`, `IO.inspect`,
    `Mix.shell/0`, or `Mix.Shell.IO` outside `lib/ancora/output.ex` and
    `lib/ancora/output/`.
  priority: must
  stability: stable
- id: ancora.tasks.verdict_grammar
  statement: >-
    `Ancora.Output.Verdict.emit/2` shall be the only producer of the string
    `result=`. `Ancora.Output.Verdict.pass?/1` shall be the only pass
    predicate used by both the emitter and gated exit path, with explicit
    `fail` taking precedence over explicit `pass`, then finding counts. The
    grammar shall be exactly `spec.check result=pass`,
    `spec.check result=fail tier=<usage|env|validate|branch> errors=<E>
    warnings=<W>`, `spec.validate result=pass`, and `spec.validate
    result=fail tier=<usage|env|validate> errors=<E> warnings=<W>`. Only
    `spec.check` and `spec.validate` shall emit a verdict, and it shall be
    the last line on stdout.
  priority: must
  stability: stable
- id: ancora.tasks.gated_emission_paths
  statement: >-
    Every task shall run inside `Ancora.Output.gated/2` or
    `Ancora.Output.gated/3`, which
    classifies the outcome as `:ok`, `:usage`, `:env`, or `:internal`.
    The wrapped function returns `{:ok, report}`, `{:usage, message}`,
    `{:env, message}`, or `{:internal, exception}`; any raised exception
    is classified `:internal`. For gate tasks, the first three shall emit the
    verdict; `:internal` shall re-raise with no verdict line and a non-zero exit.
    Report tasks (`prime`, `next`, `status`, `review`, `init`,
    `decision.new`) shall route their success and error paths through the wrapper.
    Their error paths shall print the message and exit 1 without a verdict. A missing
    `.spec/` corpus shall follow the environment path, with `spec.check`
    naming `mix spec.init` before its verdict and `spec.status` exiting 1
    without a verdict.
  priority: must
  stability: stable
- id: ancora.tasks.no_result_leak
  statement: >-
    No human-readable Output formatter other than the verdict emitter shall
    produce a line containing `result=`, for any report, finding, summary, or
    guidance value. JSON shall preserve its values and its encoded line shall
    not match the verdict grammar. Both rules shall be property-tested over
    generated reports.
  priority: must
  stability: stable
- id: ancora.tasks.stderr_pinning
  statement: >-
    `[CONFIG]` diagnostics and Logger output shall go to stderr, never
    stdout. Config, severity, and trailer diagnostics shall call
    `Ancora.Output.config_diagnostic/1`, and the static writer test shall reject
    direct stdout or stderr writes outside the Output modules. Subprocess tests shall capture the two streams separately and
    assert the verdict is the last stdout line while diagnostics appear only
    on stderr.
  priority: must
  stability: stable
- id: ancora.tasks.finding_line_format
  statement: >-
    Every finding of every family shall print as `[SEV] <subject> <code>
    <file> :: <message>`, sorted warnings first, then info (when shown), then
    errors last, followed by `branch base=<ref> changed_files=<N>
    findings=<N> (total error=E warning=W info=I hidden: default=D trailer=T
    ack=A)` where all three severity counts include visible and hidden findings,
    followed by guidance lines `branch impacted_subjects=…` and `branch
    next=…`. The summary line shall be `checked subjects=<N> requirements=<N>
    errors=<E> warnings=<W>`; no line beginning `validate status=` shall exist.
  priority: must
  stability: stable
- id: ancora.tasks.read_protocol_constant
  statement: >-
    `Ancora.Output.read_protocol/0` shall return the sentence "The verdict is
    the last stdout line: `spec.check result=…`. A non-zero exit with no
    verdict line means the run crashed before the gate finished — treat it as
    failure." `mix help spec.check` and `spec.prime`'s loop footer shall quote
    it from the constant.
  priority: must
  stability: stable
- id: ancora.tasks.check_flags
  statement: >-
    `mix spec.check` shall accept exactly `--base <ref>`, `--verbose`,
    `--debug`, `--root <dir>`, `--spec-dir <dir>`, `--json`, and
    `--explain-acks`. With `--json` it shall print the full report map as JSON
    to stdout with the verdict line still last. `--explain-acks` shall list
    only findings whose `severity_source` is `:trailer` or `:ack`, independent
    of `--verbose` and `ANCORA_SHOW_INFO`. `--spec-dir` shall select the ancora
    workspace that contains `specs/`, and omitting it shall select `.spec`.
    `--no-run-commands`, `--min-strength`,
    `--command-timeout-ms`, `--accept-drift`, `--test-tags`, and `--output`
    shall be usage errors.
  priority: must
  stability: stable
- id: ancora.tasks.validate_flags
  statement: >-
    `mix spec.validate` shall accept exactly `--strict`, `--debug`, `--root
    <dir>`, and `--spec-dir <dir>`. `--output` and `--run-commands` shall be
    usage errors.
  priority: must
  stability: stable
- id: ancora.tasks.json_report
  statement: >-
    `mix spec.check --json` shall emit a version 1 JSON report for ok, usage,
    environment, and branch outcomes. Every report shall have exactly the
    top-level keys `version`, `findings`, `all_findings`, `checked`, `branch`,
    `guidance`, `message`, `errors`, `warnings`, `tier`, and `fail`;
    `checked`, `branch`, and `guidance` shall always be maps with the same
    nested keys, while unavailable values shall be null, empty lists, or zero.
    `Ancora.Output.json_payload/1` shall encode through `Ancora.Json.encode!/1`.
    Consumers shall select the last stdout line that parses as JSON. The
    verdict shall follow it as the final stdout line.
  priority: must
  stability: stable
- id: ancora.tasks.report_task_flags
  statement: >-
    `mix spec.prime` shall accept `--base`, `--since`, `--root`, and
    `--spec-dir`; `mix spec.next` shall accept `--base`, `--since`, and
    `--verbose`; `mix spec.status` shall accept `--root` and `--spec-dir`;
    `mix spec.review` shall accept `--root`, `--spec-dir`, `--base`, `--output`
    (default `_build/spec_review.html`), and `--open`, with `-r` and `-o`
    aliases; `mix spec.init` shall accept `--root` and `--force`, with `-r`
    and `-f` aliases; `mix spec.decision.new` shall take a `DECISION_ID`
    argument with `--root`, `--title`, and `--force`, with `-r` and `-f`
    aliases. Every task moduledoc shall have an Options section listing each
    flag, its argument, aliases, and default. For the five tasks that accept
    `--spec-dir`, the flag shall select the ancora workspace that contains
    `specs/` and shall default to `.spec`. `--json` shall be a usage error
    on every task but `spec.check`. `--bugfix`, `--run-commands`, and
    `--min-strength` shall be usage errors everywhere.
  priority: must
  stability: stable
- id: ancora.tasks.next_labels_verbatim
  statement: >-
    `mix spec.next` shall print the specled_ex classification and
    reconciliation labels verbatim (`covered local change`, `needs subject
    updates`, `needs decision update`, `ready for check`, and their
    siblings), the impacted subjects with their derived-footprint files, and
    exactly one suggested command. When both are supplied, `--since` shall
    take precedence over `--base`.
  priority: must
  stability: stable
- id: ancora.tasks.status_derived_report
  statement: >-
    `mix spec.status` shall print `Spec Led Status`, `subjects=<N>
    decisions=<N> requirements=<N>`, a derived-set report `derived
    subjects=<N> empty=<E> thin(<3)=<T>`, and per-subject rows `<id>
    derived=<N> generated=<P>+<D> tests=<F> unresolved=<U>` where `<P>` counts
    project-macro-generated and `<D>` dep-generated bindings, with an
    `acknowledged` label on subjects carrying an `overrides:` entry. `thin`
    shall be the constant 3, documented as non-configurable. Corpus findings
    shall not make this report task fail. `spec.status` and `spec.check` shall
    reject an override naming an unknown requirement id with
    `config/invalid_value` and ignore the entry. Environment and usage errors
    shall still exit 1 through `Ancora.Output.gated/2` without a verdict line.
  priority: must
  stability: evolving
- id: ancora.tasks.prime_loop
  statement: >-
    `mix spec.prime --base HEAD` shall print a header, the status body, the
    next body, and loop bullets ending with the check command and the
    exact `Ancora.Output.read_protocol/0` sentence, and shall be the documented
    session-start idiom. Prime shall build the status derivation once and pass
    that report to Next; standalone Next runs shall build their own status.
  priority: must
  stability: evolving
- id: ancora.tasks.mix_bootstrap_posture
  statement: >-
    Every task shall require `deps.loadpaths` and shall never trigger
    compilation of the target project. The task moduledocs shall state that a
    cold checkout's first run may print dependency compilation lines before
    ancora output. `spec.check` and `spec.validate` establish this posture for
    the gate tasks without loading the target's Mix project.
  priority: must
  stability: stable
- id: ancora.tasks.exit_codes
  statement: >-
    Exit status shall be 0 on success and 1 on every failure; the verdict
    `tier=` disambiguates the cause. No other exit code shall be used.
  priority: must
  stability: stable
- id: ancora.tasks.ci_explicit_base
  statement: >-
    The CI smoke step shall pass `--base` explicitly. Pull requests shall use
    the fetched `origin/${github.base_ref}`; push events shall use
    `github.event.before`; an all-zero push base shall skip the smoke step;
    workflow dispatch shall use the fetched default branch.
  priority: must
  stability: stable
```

## Scenarios

```yaml spec-scenarios
- id: ancora.tasks.scenario.task_list
  given:
    - the compiled package
  when:
    - `Mix.Task.all_modules/0` is filtered to the `spec.` prefix
  then:
    - exactly the eight named tasks are present
  covers:
    - ancora.tasks.exactly_eight
- id: ancora.tasks.scenario.forbidden_writer_test
  given:
    - every file under `lib/` parsed to AST
  when:
    - the static writer test walks each AST
  then:
    - no `IO.puts`, `IO.write`, `IO.inspect`, `Mix.shell`, or `Mix.Shell.IO` call exists outside the Output modules
  covers:
    - ancora.tasks.single_stdout_writer
- id: ancora.tasks.scenario.green_golden
  given:
    - a warmed fixture project with a clean corpus and `--base HEAD`
  when:
    - `mix spec.check` runs as a subprocess with stdout and stderr captured separately
  then:
    - exit status is 0
    - the last stdout line is `spec.check result=pass`
  covers:
    - ancora.tasks.verdict_grammar
    - ancora.tasks.gated_emission_paths
    - ancora.tasks.exit_codes
- id: ancora.tasks.scenario.findings_golden
  given:
    - a warmed fixture project with one drift finding and one info finding
  when:
    - `mix spec.check` runs as a subprocess
  then:
    - exit status is 1
    - finding lines precede the branch summary, guidance lines, and verdict
    - the last stdout line matches `spec.check result=fail tier=branch errors=1 warnings=0`
  covers:
    - ancora.tasks.verdict_grammar
    - ancora.tasks.finding_line_format
    - ancora.tasks.gated_emission_paths
- id: ancora.tasks.scenario.env_golden
  given:
    - a fixture project with no resolvable base
  when:
    - `mix spec.check` runs as a subprocess
  then:
    - exit status is 1
    - the last stdout line is `spec.check result=fail tier=env`
    - the remedy message is on stdout before the verdict
  covers:
    - ancora.tasks.gated_emission_paths
- id: ancora.tasks.scenario.missing_corpus_env
  given:
    - a git project with no `.spec/` directory
  when:
    - `mix spec.check --base HEAD` runs as a subprocess
  then:
    - stdout names `mix spec.init`
    - the last stdout line is the environment failure verdict
    - stderr contains no internal exception
  covers:
    - ancora.tasks.gated_emission_paths
- id: ancora.tasks.scenario.usage_golden
  given:
    - `mix spec.check --no-run-commands`
  when:
    - the task runs as a subprocess
  then:
    - exit status is 1
    - the last stdout line is `spec.check result=fail tier=usage`
  covers:
    - ancora.tasks.gated_emission_paths
    - ancora.tasks.check_flags
- id: ancora.tasks.scenario.internal_raise_has_no_verdict
  given:
    - a fixture deliberately broken so the gate raises inside stage 4
  when:
    - `mix spec.check` runs as a subprocess
  then:
    - exit status is non-zero
    - no stdout line contains `result=`
  covers:
    - ancora.tasks.gated_emission_paths
- id: ancora.tasks.scenario.json_golden
  given:
    - a warmed fixture project with one growth finding
  when:
    - `mix spec.check --json` runs as a subprocess
  then:
    - the last stdout line that parses as JSON contains the finding
    - its keys match the ok, environment, and usage JSON reports
    - its version is 1 and the last stdout line is the verdict
  covers:
    - ancora.tasks.check_flags
    - ancora.tasks.json_report
- id: ancora.tasks.scenario.explain_acks
  given:
    - one ack-sourced finding, one trailer-sourced finding, and one default-info finding
  when:
    - `mix spec.check --explain-acks` runs without `--verbose`
  then:
    - the ack- and trailer-sourced findings are listed
    - the default-info finding is not listed
  covers:
    - ancora.tasks.check_flags
- id: ancora.tasks.scenario.result_never_leaks
  given:
    - stream_data generated reports, findings, and guidance values containing the substring `result=`
  when:
    - every Output formatter renders them
  then:
    - no rendered non-verdict line contains `result=`
  covers:
    - ancora.tasks.no_result_leak
- id: ancora.tasks.scenario.config_diagnostic_on_stderr
  given:
    - a fixture with malformed config.yml
  when:
    - `mix spec.check` runs as a subprocess
  then:
    - a `[CONFIG]` line is on stderr
    - stdout contains no `[CONFIG]` line and ends with the verdict
  covers:
    - ancora.tasks.stderr_pinning
- id: ancora.tasks.scenario.no_validate_status_line
  given:
    - any `mix spec.validate` run
  when:
    - stdout is captured
  then:
    - no line begins with `validate status=`
    - one line matches `checked subjects=<N> requirements=<N> errors=<E> warnings=<W>`
  covers:
    - ancora.tasks.finding_line_format
- id: ancora.tasks.scenario.help_quotes_read_protocol
  given:
    - `mix help spec.check`
  when:
    - its output is captured
  then:
    - it contains `Ancora.Output.read_protocol/0` verbatim
  covers:
    - ancora.tasks.read_protocol_constant
- id: ancora.tasks.scenario.validate_rejects_output
  given:
    - `mix spec.validate --output x.json`
  when:
    - the task runs
  then:
    - the verdict is `spec.validate result=fail tier=usage`
  covers:
    - ancora.tasks.validate_flags
- id: ancora.tasks.scenario.json_rejected_on_reports
  given:
    - `mix spec.prime --json`, `mix spec.next --json`, `mix spec.status --json`
  when:
    - each runs
  then:
    - each exits 1 with a usage message and no verdict line
  covers:
    - ancora.tasks.report_task_flags
- id: ancora.tasks.scenario.status_always_zero
  given:
    - a corpus with errors
  when:
    - `mix spec.status` runs
  then:
    - exit status is 0
    - the derived-set report line is present
  covers:
    - ancora.tasks.status_derived_report
- id: ancora.tasks.scenario.status_missing_corpus
  given:
    - a project with no `.spec/` directory
  when:
    - `mix spec.status` runs
  then:
    - it exits 1 with a message naming `mix spec.init`
    - stdout contains no verdict
  covers:
    - ancora.tasks.status_derived_report
- id: ancora.tasks.scenario.status_splits_generated
  given:
    - a subject with one project-macro-generated and two dep-generated bindings
  when:
    - `mix spec.status` runs
  then:
    - the subject row shows `generated=1+2`
  covers:
    - ancora.tasks.status_derived_report
- id: ancora.tasks.scenario.next_labels
  given:
    - a diff touching one subject's watched function and its spec
  when:
    - `mix spec.next` runs
  then:
    - the output contains the label `ready for check` and exactly one suggested command
  covers:
    - ancora.tasks.next_labels_verbatim
- id: ancora.tasks.scenario.since_precedes_base
  given:
    - `--base` names an unresolvable ref and `--since` is `HEAD`
  when:
    - `mix spec.next` runs
  then:
    - the report succeeds with `base=HEAD`
  covers:
    - ancora.tasks.next_labels_verbatim
- id: ancora.tasks.scenario.scaffold_errors_are_gated
  given:
    - invalid arguments for `spec.init` and `spec.decision.new`
  when:
    - each task runs
  then:
    - the wrapper prints the usage message and exits 1 without a verdict
  covers:
    - ancora.tasks.gated_emission_paths
- id: ancora.tasks.scenario.ci_event_bases
  given:
    - the repository CI workflow
  when:
    - the smoke step selects a base
  then:
    - pull requests use the fetched base branch
    - pushes use the before SHA and skip an all-zero SHA
    - workflow dispatch uses the fetched default branch
  covers:
    - ancora.tasks.ci_explicit_base
- id: ancora.tasks.scenario.prime_footer
  given:
    - `mix spec.prime --base HEAD` in a fixture
  when:
    - stdout is captured
  then:
    - the final bullets contain `mix spec.check` and the read-protocol sentence
  covers:
    - ancora.tasks.prime_loop
- id: ancora.tasks.scenario.no_project_compile
  given:
    - a fixture project whose `lib/` contains a file with a compile error
  when:
    - `mix spec.check --root <fixture> --base HEAD` runs from the ancora checkout
  then:
    - the run completes with a verdict line
    - no compile error for the fixture is raised
  covers:
    - ancora.tasks.mix_bootstrap_posture
```

## Verification

```yaml spec-verification
- kind: tagged_tests
  covers:
    - ancora.tasks.exactly_eight
    - ancora.tasks.single_stdout_writer
    - ancora.tasks.verdict_grammar
    - ancora.tasks.gated_emission_paths
    - ancora.tasks.no_result_leak
    - ancora.tasks.stderr_pinning
    - ancora.tasks.finding_line_format
    - ancora.tasks.read_protocol_constant
    - ancora.tasks.check_flags
    - ancora.tasks.json_report
    - ancora.tasks.validate_flags
    - ancora.tasks.report_task_flags
    - ancora.tasks.next_labels_verbatim
    - ancora.tasks.status_derived_report
    - ancora.tasks.prime_loop
    - ancora.tasks.mix_bootstrap_posture
    - ancora.tasks.exit_codes
    - ancora.tasks.ci_explicit_base
```
