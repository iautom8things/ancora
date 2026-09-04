# Finding Registry, Severity, Trailer, and Config

The closed 31-code registry, per-finding severity resolution, the `Spec-Ack:`
trailer, and the `.spec/config.yml` schema with per-subject overrides.

## Intent

One flat vocabulary with truthful family prefixes, small enough to fit in a
triage table, owned by one module that config validation, output, docs, and
the review artifact all read. Adding a code is a spec change in this corpus.

Count note: the planning documents say 26 codes. Enumerating the registry
table after the `spec/prose_too_short` cut gave 30; the 26 was a carried
miscount. The primary/transitive drift split adds the 31st code. The
enumerated list below is authoritative.
Severity has one precedence chain, silence lives in the repo where review
can see it, and the trailer can only lower.

Modules: `Ancora.Finding`, `Ancora.Severity`, `Ancora.Trailer`,
`Ancora.Config`, `Ancora.ModalClass`.

```yaml spec-meta
id: ancora.findings
kind: module
status: active
summary: Closed 31-code finding registry, severity precedence, Spec-Ack trailer grammar, and config.yml schema with per-subject overrides.
decisions:
  - ancora.decision.field_friction_response
  - ancora.decision.slimmed_governance
```

## Requirements

```yaml spec-requirements
- id: ancora.findings.registry_closed
  statement: >-
    Ancora.Finding shall own exactly 31 codes, each with a family, a default
    severity, and a message function, and shall be the single source every
    other module reads. The codes are `derived/drift`,
    `derived/drift_transitive`, `derived/growth`, `derived/shrink`,
    `derived/unresolved_calls`, `derived/unparseable_source`,
    `derived/unanchored_subject`, `change/uncovered_file`,
    `change/missing_decision`, `tags/new_requirement_untagged`,
    `tags/parse_error`, `tags/dynamic_value`, `tags/requirement_untagged`,
    `tags/unknown_requirement`, `append/requirement_deleted`,
    `append/must_downgraded`, `format/retired_construct`, `spec/parse_error`,
    `spec/duplicate_id`, `spec/invalid_id`, `spec/missing_field`,
    `spec/unknown_reference`, `spec/requirement_unverified`,
    `adr/parse_error`, `adr/missing_section`, `adr/affects_empty`,
    `adr/affects_unresolved`, `overlap/duplicate_covers`,
    `overlap/must_stem_collision`, `config/unknown_key`, and
    `config/invalid_value`. A code missing any of the three parts shall fail
    the registry closure test.
  priority: must
  stability: stable
- id: ancora.findings.registry_defaults
  statement: >-
    Registry defaults shall be: error for `derived/drift`,
    `derived/unparseable_source`, `append/*`, `spec/parse_error`,
    `spec/duplicate_id`, `spec/invalid_id`, `spec/missing_field`,
    `spec/unknown_reference`, `adr/parse_error`, `adr/missing_section`,
    `adr/affects_unresolved`, `overlap/*`, and `tags/parse_error`; warning
    for `derived/growth`, `derived/shrink`, `derived/unanchored_subject`,
    `change/uncovered_file`, `change/missing_decision`,
    `tags/new_requirement_untagged`, `tags/unknown_requirement`,
    `format/retired_construct`, `adr/affects_empty`, `config/unknown_key`,
    and `config/invalid_value`; info for `derived/unresolved_calls`,
    `tags/dynamic_value`, `tags/requirement_untagged`,
    `spec/requirement_unverified`, and `derived/drift_transitive`.
  priority: must
  stability: evolving
- id: ancora.findings.messages_carry_remedy
  statement: >-
    Every code's message function shall produce text that names the subject
    or file concerned and the action that clears the finding.
    `derived/unanchored_subject`'s message shall name the per-subject
    `overrides:` entry as the remedy for integration-only subjects.
  priority: must
  stability: evolving
- id: ancora.findings.severity_precedence
  statement: >-
    Ancora.Severity shall resolve each finding as: config `off` absorbs
    everything; otherwise a `Spec-Ack:` trailer downgrade applies; otherwise
    the config `severities:` value; otherwise the registry default. The
    resolved finding shall carry `severity_source` as one of `:config`,
    `:trailer`, `:ack`, `:default`. A finding suppressed by subject
    acknowledgment shall be retained at info with `severity_source: :ack`,
    not destroyed. A finding resolved to `off` shall not be emitted or counted.
  priority: must
  stability: stable
- id: ancora.findings.info_visibility
  statement: >-
    Findings at `info` shall be printed only when `--verbose` is passed or
    `ANCORA_SHOW_INFO=1` is set, and shall never affect exit status. The
    branch summary shall report the hidden count per severity source
    (`default`, `trailer`, and `ack`). A preflight environment failure
    represented as JSON shall keep `all_findings` empty rather than fabricate
    a finding for the target-read error.
  priority: must
  stability: stable
- id: ancora.findings.trailer_grammar
  statement: >-
    Ancora.Trailer shall parse `Spec-Ack: <code>=<info|warning>` from
    `git log <base>..HEAD --format=%B`, accept only registry codes, apply
    downgrade only (never `error`, never `off`, never higher than the
    resolved config severity), and support no presets. An unknown code or
    severity shall emit a `[CONFIG]` warning on stderr and be ignored, never
    silently dropped.
  priority: must
  stability: stable
- id: ancora.findings.config_schema
  statement: >-
    Ancora.Config shall accept exactly the top-level keys `default_base`,
    `test_paths`, `lib_paths`, `severities`, and `overrides`. `severities:`
    is one map whose keys are validated against the registry. An unknown
    top-level key or an unknown code in `severities:` shall produce
    `config/unknown_key`; a bad severity value shall produce
    `config/invalid_value`; both codes shall be non-tunable. Malformed YAML
    shall degrade to defaults with a `[CONFIG]` diagnostic on stderr.
    `ANCORA_SHOW_INFO` shall be the only environment variable read.
  priority: must
  stability: stable
- id: ancora.findings.per_subject_overrides
  statement: >-
    Each `overrides:` entry shall carry `subject`, `code`, `severity`, a
    required non-empty `reason`, and an optional `requirement:` that narrows
    the override to findings attributed to that requirement id. An entry
    without `requirement:` shall apply subject-wide as before. An entry naming
    an unknown subject, requirement id, or code, or missing `reason`, shall
    produce `config/invalid_value` and be ignored. `spec.status` shall label
    overridden subjects `acknowledged`.
  priority: must
  stability: evolving
- id: ancora.findings.config_coversioned_note
  statement: >-
    The Ancora.Config moduledoc shall state that `.spec/config.yml` and the
    ancora version in `mix.lock` travel together in git, and that a new code
    is configured in the same PR that bumps the dependency.
  priority: should
  stability: stable
```

## Scenarios

```yaml spec-scenarios
- id: ancora.findings.scenario.registry_closure
  given:
    - the Ancora.Finding registry
  when:
    - the closure test enumerates it
  then:
    - exactly 31 codes exist
    - each has a family, a default, and a message function that returns a non-empty string
  covers:
    - ancora.findings.registry_closed
    - ancora.findings.registry_defaults
- id: ancora.findings.scenario.unanchored_message_names_override
  given:
    - a `derived/unanchored_subject` finding for `atlas.web.sessions`
  when:
    - its message is rendered
  then:
    - the text contains `overrides:` and the subject id
  covers:
    - ancora.findings.messages_carry_remedy
- id: ancora.findings.scenario.off_beats_trailer
  given:
    - "config `severities: {derived/growth: off}`"
    - "a trailer `Spec-Ack: derived/growth=warning`"
  when:
    - severity is resolved for a growth finding
  then:
    - the finding is not emitted
  covers:
    - ancora.findings.severity_precedence
- id: ancora.findings.scenario.trailer_downgrades_config
  given:
    - "config `severities: {derived/drift: error}`"
    - "a trailer `Spec-Ack: derived/drift=warning`"
  when:
    - severity is resolved for a drift finding
  then:
    - "the severity is `warning` with `severity_source: :trailer`"
  covers:
    - ancora.findings.severity_precedence
    - ancora.findings.trailer_grammar
- id: ancora.findings.scenario.trailer_cannot_raise
  given:
    - "a trailer `Spec-Ack: derived/unresolved_calls=error`"
  when:
    - trailers are parsed
  then:
    - a `[CONFIG]` line on stderr names the rejected severity
    - the finding stays at its resolved severity
  covers:
    - ancora.findings.trailer_grammar
- id: ancora.findings.scenario.unknown_trailer_code
  given:
    - "a trailer `Spec-Ack: branch_guard_realization_drift=info`"
  when:
    - trailers are parsed
  then:
    - a `[CONFIG]` line on stderr names the unknown code
    - no severity changes
  covers:
    - ancora.findings.trailer_grammar
- id: ancora.findings.scenario.info_hidden_by_default
  given:
    - a corpus with one `info` finding and nothing else
  when:
    - `mix spec.check` runs without `--verbose`
  then:
    - no finding line is printed
    - the summary reports one hidden info finding
    - the verdict is `result=pass`
  covers:
    - ancora.findings.info_visibility
- id: ancora.findings.scenario.unknown_config_key
  given:
    - a config.yml with a top-level `test_tags:` block
  when:
    - config is loaded
  then:
    - `config/unknown_key` fires naming `test_tags`
    - "setting `config/unknown_key: off` in the same file does not silence it"
  covers:
    - ancora.findings.config_schema
- id: ancora.findings.scenario.unknown_severity_code
  given:
    - "`severities: {branch_guard_unmapped_change: warning}`"
  when:
    - config is loaded
  then:
    - `config/unknown_key` fires naming the code
  covers:
    - ancora.findings.config_schema
- id: ancora.findings.scenario.malformed_yaml_degrades
  given:
    - a config.yml that is not valid YAML
  when:
    - config is loaded
  then:
    - defaults are used
    - a `[CONFIG]` line appears on stderr and nothing about it on stdout
  covers:
    - ancora.findings.config_schema
- id: ancora.findings.scenario.override_missing_reason
  given:
    - an `overrides:` entry with subject, code, severity, and no `reason`
  when:
    - config is loaded
  then:
    - `config/invalid_value` fires naming the entry
    - the override is not applied
  covers:
    - ancora.findings.per_subject_overrides
- id: ancora.findings.scenario.override_scoped_to_subject
  given:
    - an override for subject A on `derived/unanchored_subject` at `info`
    - subjects A and B both unanchored
  when:
    - severities are resolved
  then:
    - "A resolves to `info` with `severity_source: :config`"
    - B resolves to `warning`
  covers:
    - ancora.findings.per_subject_overrides
- id: ancora.findings.scenario.override_scoped_to_requirement
  given:
    - requirements R1 and R2 of subject A both fire `tags/requirement_untagged`
    - "an override names subject A, that code, `requirement: R1`, and severity `info`"
  when:
    - severities are resolved
  then:
    - "R1 resolves to `info` with `severity_source: :config`"
    - R2 stays at its registry default
  covers:
    - ancora.findings.per_subject_overrides
- id: ancora.findings.scenario.moduledoc_states_coversioning
  given:
    - the compiled Ancora.Config module
  when:
    - its moduledoc is read
  then:
    - it mentions `mix.lock` and configuring a new code in the same PR as the dependency bump
  covers:
    - ancora.findings.config_coversioned_note
```

## Verification

```yaml spec-verification
- kind: tagged_tests
  covers:
    - ancora.findings.registry_closed
    - ancora.findings.registry_defaults
    - ancora.findings.messages_carry_remedy
    - ancora.findings.severity_precedence
    - ancora.findings.info_visibility
    - ancora.findings.trailer_grammar
    - ancora.findings.config_schema
    - ancora.findings.per_subject_overrides
    - ancora.findings.config_coversioned_note
```
