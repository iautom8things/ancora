# Parsing and Corpus Assembly

The spec-file block grammar, ADR parsing, structural reference checks, and
tagged-test discovery. This is the ported core of specled_ex with the
realization constructs removed and tolerated.

## Intent

The spec format is a stability requirement: four consuming repos carry
corpora written against specled_ex, and Atlas reads spec files at runtime
through the parser. Ancora parses that format unchanged, tolerates the
constructs it retired so a half-stripped corpus still parses on both diff
sides, and reports the retired constructs as a named finding so migration
completeness is proven by the gate rather than by grep.

Module origins (recorded in NOTICE): `Ancora.Parser`, `Ancora.Schema.*`,
`Ancora.Index`, `Ancora.DecisionParser`, `Ancora.DecisionParser.Affects`,
`Ancora.TagScanner`, `Ancora.TagFindings`, `Ancora.Overlap`,
`Ancora.Verifier` (structural keeper) are ports or surgeries of the
spec_led_ex modules of the same role.

```yaml spec-meta
id: ancora.parsing
kind: module
status: active
summary: "Spec and ADR block grammar, retired-construct tolerance, structural reference checks, and @tag spec: discovery."
decisions:
  - ancora.decision.no_execution_no_state
  - ancora.decision.requirement_scoped_append_authorization
  - ancora.decision.cli_json_contract
  - ancora.decision.retirement_vocabulary
  - ancora.decision.invalid_spec_meta
```

## Requirements

```yaml spec-requirements
- id: ancora.parsing.block_grammar_unchanged
  statement: >-
    Ancora.Parser shall parse the specled_ex block grammar unchanged: fenced
    `yaml spec-meta`, `yaml spec-requirements`, `yaml spec-scenarios`, and
    `yaml spec-verification` blocks inside a `*.spec.md` file. A spec file
    that parses under specled_ex 0.17 shall parse under ancora to the same
    subject id, requirement ids, and scenario ids. The only file a fresh
    scaffold puts in front of Ancora.Parser is
    `.spec/specs/project.core.spec.md`; it shall arrive as the shipped
    template's exact bytes, never EEx-evaluated, so the seed subject parses to
    the ids the template declares even when that text contains literal EEx
    tags.
  priority: must
  stability: stable
- id: ancora.parsing.retired_constructs_tolerated
  statement: >-
    `realized_by:` (in spec-meta or on a requirement), `execute:` on a
    verification entry, and any verification `kind` other than `tagged_tests`
    shall be tolerated by the parser on both diff sides: parsing succeeds and
    the subject is indexed. When such a construct is present on the HEAD side,
    the gate shall emit `format/retired_construct` for it and no other
    finding. A verification `kind` that is neither `tagged_tests` nor a known
    retired kind shall emit `spec/parse_error`.
  priority: must
  stability: stable
- id: ancora.parsing.structural_references
  statement: >-
    Ancora.Verifier shall emit `spec/unknown_reference` for a scenario
    `covers:` entry, a verification `covers:` entry, or a spec-meta
    `decisions:` entry that names an id not present in the corpus;
    `spec/duplicate_id` for any subject, requirement, scenario, or decision id
    declared twice across the corpus; `spec/invalid_id` for a requirement,
    scenario, decision, or reference id that does not match the
    dotted-identifier format; and `spec/missing_field` for a requirement or
    scenario entry missing a required field. When spec-meta fails schema
    validation, Ancora.Parser shall store the `:rejected` marker under
    `"meta"` and emit `spec/parse_error`. For a malformed subject id or an
    omitted required field, that shall be the only `spec/*` finding and its
    detail shall name the rejected field. A spec file without a spec-meta
    block shall emit one blocking `spec/missing_field` finding naming the file
    and shall not count as a checked subject. Ancora.Index shall read known
    fields from validated atom-keyed schema structs and raw string-keyed maps
    without creating atoms from input, and shall return only a non-empty
    binary or nil for a subject id. Index assembly shall return a missing
    authored `specs/` directory as error data that names the requested
    workspace and directory. Every corpus-reading Mix task shall handle absent
    and malformed metadata, and a missing directory, without raising.
  priority: must
  stability: stable
- id: ancora.parsing.requirement_unverified
  statement: >-
    A requirement with no `tagged_tests` verification entry whose `covers:`
    names it shall produce `spec/requirement_unverified` (registry default
    `info`).
  priority: must
  stability: evolving
- id: ancora.parsing.adr_grammar
  statement: >-
    Ancora.DecisionParser shall parse ADR frontmatter `id`, `status`, `date`,
    `affects:`, and optional `retires:` plus the Context, Decision, and
    Consequences sections. `change_type`, `supersedes`, `replaces`, and
    `reverses_what` shall be accepted and ignored without any finding. A
    missing section shall emit `adr/missing_section`; malformed frontmatter
    shall emit `adr/parse_error`; an empty `affects:` shall emit
    `adr/affects_empty`; an `affects:` entry naming an id that is neither in
    the corpus nor repeated in `retires:` shall emit
    `adr/affects_unresolved`.
  priority: must
  stability: stable
- id: ancora.parsing.append_authorization_is_requirement_scoped
  statement: >-
    Ancora.AppendOnly shall suppress `append/requirement_deleted` or
    `append/must_downgraded` only when an accepted ADR's `affects:` list names
    the exact requirement id, except for deletion authorized through the
    retirement vocabulary. A subject id shall remain valid for affects
    resolution and documentation, but shall not by itself authorize deleting
    or downgrading any requirement in that subject.
  priority: must
  stability: stable
- id: ancora.parsing.retirement_vocabulary
  statement: >-
    An accepted ADR may authorize requirement deletion through `retires:`.
    An exact requirement id shall authorize only that requirement's deletion,
    while a subject id shall authorize deletion of every requirement that
    belonged to that subject. `retires:` shall not authorize a `must` to
    `should` downgrade. An id repeated in `affects:` and `retires:` may be
    absent from the current index without `adr/affects_unresolved`. The Zoi
    decision schema shall accept the optional list, and the spec.init decision
    guidance shall teach authors to repeat a removed id in both fields.
  priority: must
  stability: stable
- id: ancora.parsing.tag_discovery
  statement: >-
    Ancora.TagScanner shall discover `@tag spec:`, `@moduletag spec:`, and
    `@describetag spec:` values in every `**/*_test.exs` under the configured
    `test_paths`, including tags inside `describe` blocks and
    for-comprehension bodies, and shall fold requirement ids up to subject ids
    for the detector. A non-literal tag value shall be recorded as
    `tags/dynamic_value` and never guessed; a test file that fails to parse
    shall emit `tags/parse_error`; a tag naming an id absent from the corpus
    shall emit `tags/unknown_requirement`; a requirement with no tag anywhere
    shall emit `tags/requirement_untagged`.
  priority: must
  stability: stable
- id: ancora.parsing.overlap_checks
  statement: >-
    Two verification entries in the corpus whose `covers:` lists are identical
    shall emit `overlap/duplicate_covers`; two `must` requirements in one
    subject whose statements share a normalized stem shall emit
    `overlap/must_stem_collision`.
  priority: must
  stability: evolving
- id: ancora.parsing.stable_public_api
  statement: >-
    `Ancora.Parser.parse_file/2`, `Ancora.DecisionParser.parse_file/2`,
    `Ancora.check/2`, and `Ancora.validate/2` shall be the only semver-stable
    public functions: all four exported and documented as stable in their
    moduledocs and in the README, with their return shapes unchanged within a
    major version. Every other module and function is internal.
  priority: must
  stability: stable
- id: ancora.parsing.consumer_corpora_parse
  statement: >-
    One real spec file from each consuming repo (Atlas, Engage, Builder,
    Argos), taken as a fixture, shall parse with no finding other than
    `format/retired_construct`.
  priority: should
  stability: evolving
```

## Scenarios

```yaml spec-scenarios
- id: ancora.parsing.scenario.specled_spec_parses_identically
  given:
    - a spec file valid under specled_ex 0.17 with one subject, three requirements, and two scenarios
  when:
    - Ancora.Parser.parse_file/2 is called on it
  then:
    - the subject id, the three requirement ids, and the two scenario ids match the specled_ex parse exactly
  covers:
    - ancora.parsing.block_grammar_unchanged
    - ancora.parsing.stable_public_api
- id: ancora.parsing.scenario.library_entry_points
  given:
    - a clean git corpus
  when:
    - `Ancora.check/2` and `Ancora.validate/2` are called
  then:
    - both return ok reports from their production pipelines
    - all four stable functions are documented as semver-stable
  covers:
    - ancora.parsing.stable_public_api
- id: ancora.parsing.scenario.retired_construct_pair
  given:
    - "two copies of one spec file, one carrying `realized_by:` and `execute: true`, one stripped"
  when:
    - the carrying copy is on the base side and the stripped copy on HEAD
  then:
    - both sides parse to the same ids
    - no `format/retired_construct` finding fires
  covers:
    - ancora.parsing.retired_constructs_tolerated
- id: ancora.parsing.scenario.retired_construct_on_head
  given:
    - "a spec file on HEAD with a verification entry `kind: source_file` and `execute: false`"
  when:
    - the gate runs
  then:
    - `format/retired_construct` fires once for the file
    - no other finding names that verification entry
  covers:
    - ancora.parsing.retired_constructs_tolerated
- id: ancora.parsing.scenario.garbage_kind_is_parse_error
  given:
    - "a verification entry with `kind: bananas`"
  when:
    - the corpus is indexed
  then:
    - `spec/parse_error` fires naming the file and the entry
  covers:
    - ancora.parsing.retired_constructs_tolerated
- id: ancora.parsing.scenario.unknown_cover_reference
  given:
    - a scenario whose `covers:` names `ancora.nope.missing`
  when:
    - the structural verifier runs
  then:
    - `spec/unknown_reference` fires naming the scenario id and the dangling id
  covers:
    - ancora.parsing.structural_references
- id: ancora.parsing.scenario.duplicate_requirement_id
  given:
    - two spec files each declaring requirement `ancora.x.same`
  when:
    - the corpus is indexed
  then:
    - `spec/duplicate_id` fires once naming both files
  covers:
    - ancora.parsing.structural_references
- id: ancora.parsing.scenario.invalid_spec_meta
  given:
    - one spec-meta block with a malformed subject id and every required field present
    - one spec-meta block with a valid subject id and status omitted
  when:
    - each corpus-reading Mix task reads the corpus
  then:
    - the parsed subject keeps the string-keyed outer index shape and stores the `:rejected` marker under `"meta"`
    - `spec/parse_error` is the only `spec/*` finding and names the rejected id or status field
    - the rejected subject has no accepted subject-id attribution
    - no task raises and review renders no subject section for the rejected subject
    - field lookup does not create an atom for an unknown input key
  covers:
    - ancora.parsing.structural_references
    - ancora.parsing.stable_public_api
- id: ancora.parsing.scenario.absent_spec_meta
  given:
    - a spec file without a spec-meta block
  when:
    - each corpus-reading Mix task reads the corpus
  then:
    - one blocking `spec/missing_field` finding names the file
    - the file is not counted as a checked subject
    - no task raises
  covers:
    - ancora.parsing.structural_references
    - ancora.parsing.stable_public_api
- id: ancora.parsing.scenario.requirement_without_tagged_tests
  given:
    - a subject with a requirement that no `tagged_tests` entry covers
  when:
    - the structural verifier runs
  then:
    - `spec/requirement_unverified` fires at severity `info`
  covers:
    - ancora.parsing.requirement_unverified
- id: ancora.parsing.scenario.adr_with_change_type_is_silent
  given:
    - "an ADR with frontmatter `change_type: clarifies` and all three sections present"
  when:
    - Ancora.DecisionParser.parse_file/2 is called
  then:
    - parsing succeeds
    - no finding mentions `change_type`
  covers:
    - ancora.parsing.adr_grammar
- id: ancora.parsing.scenario.adr_missing_consequences
  given:
    - an ADR with Context and Decision sections but no Consequences section
  when:
    - the ADR is parsed
  then:
    - `adr/missing_section` fires naming Consequences
  covers:
    - ancora.parsing.adr_grammar
- id: ancora.parsing.scenario.adr_affects_unresolved
  given:
    - an ADR whose `affects:` lists `ancora.ghost.requirement`
    - the id is absent from both the current corpus and the ADR's `retires:` list
  when:
    - the corpus is indexed
  then:
    - `adr/affects_unresolved` fires at severity `error`
  covers:
    - ancora.parsing.adr_grammar
- id: ancora.parsing.scenario.retired_subject_validates_cold
  given:
    - a corpus from which subject `old.subject` and all of its requirements have been removed
    - "an accepted ADR that lists `old.subject` in both `affects:` and `retires:`"
  when:
    - `mix spec.validate` runs using only the current corpus
  then:
    - no `adr/affects_unresolved` finding fires
    - the verdict is `spec.validate result=pass`
  covers:
    - ancora.parsing.adr_grammar
    - ancora.parsing.retirement_vocabulary
- id: ancora.parsing.scenario.subject_affect_does_not_authorize_append_change
  given:
    - an accepted ADR whose `affects:` lists only a subject id
  when:
    - a requirement in that subject is deleted or downgraded from `must` to `should`
  then:
    - the corresponding append-only finding fires for the requirement
  covers:
    - ancora.parsing.append_authorization_is_requirement_scoped
- id: ancora.parsing.scenario.requirement_affect_authorizes_append_change
  given:
    - an accepted ADR whose `affects:` lists an exact requirement id
  when:
    - that requirement is deleted or downgraded from `must` to `should`
  then:
    - no append-only finding fires for the requirement
  covers:
    - ancora.parsing.append_authorization_is_requirement_scoped
- id: ancora.parsing.scenario.subject_retirement_authorizes_deletion
  given:
    - a subject with two requirements on the base side
    - "an accepted ADR whose `retires:` lists that subject id"
  when:
    - the whole subject is absent on HEAD
  then:
    - no `append/requirement_deleted` finding fires for either requirement
  covers:
    - ancora.parsing.retirement_vocabulary
    - ancora.parsing.append_authorization_is_requirement_scoped
- id: ancora.parsing.scenario.requirement_retirement_is_exact
  given:
    - "an accepted ADR whose `retires:` lists one requirement id"
  when:
    - a different requirement in the same subject is deleted
  then:
    - `append/requirement_deleted` fires for the deleted requirement
  covers:
    - ancora.parsing.retirement_vocabulary
- id: ancora.parsing.scenario.retirement_does_not_authorize_downgrade
  given:
    - "an accepted ADR whose `retires:` lists a subject id"
  when:
    - one of that subject's requirements remains in the corpus but moves from `must` to `should`
  then:
    - `append/must_downgraded` fires for the requirement
  covers:
    - ancora.parsing.retirement_vocabulary
- id: ancora.parsing.scenario.tag_inside_for_comprehension
  given:
    - "a test file with `for {name, input} <- cases do @tag spec: \"ancora.parsing.tag_discovery\"; test name do ... end end`"
  when:
    - Ancora.TagScanner scans the file
  then:
    - the tag is attributed to the file for subject `ancora.parsing`
  covers:
    - ancora.parsing.tag_discovery
- id: ancora.parsing.scenario.dynamic_tag_value_recorded
  given:
    - "a test file with `@tag spec: @subject <> \".x\"`"
  when:
    - the scanner runs
  then:
    - `tags/dynamic_value` is recorded for that line
    - no subject gains the file from that tag
  covers:
    - ancora.parsing.tag_discovery
- id: ancora.parsing.scenario.duplicate_covers
  given:
    - two verification entries in different subjects with identical `covers:` lists
  when:
    - the overlap check runs
  then:
    - `overlap/duplicate_covers` fires naming both entries
  covers:
    - ancora.parsing.overlap_checks
- id: ancora.parsing.scenario.consumer_fixture_parses
  given:
    - one spec file copied from each of Atlas, Engage, Builder, and Argos as fixtures
  when:
    - each is parsed and structurally verified in isolation
  then:
    - the only finding code present is `format/retired_construct`
  covers:
    - ancora.parsing.consumer_corpora_parse
```

## Verification

```yaml spec-verification
- kind: tagged_tests
  covers:
    - ancora.parsing.block_grammar_unchanged
    - ancora.parsing.retired_constructs_tolerated
    - ancora.parsing.structural_references
    - ancora.parsing.requirement_unverified
    - ancora.parsing.adr_grammar
    - ancora.parsing.append_authorization_is_requirement_scoped
    - ancora.parsing.retirement_vocabulary
    - ancora.parsing.tag_discovery
    - ancora.parsing.overlap_checks
    - ancora.parsing.stable_public_api
    - ancora.parsing.consumer_corpora_parse
```
