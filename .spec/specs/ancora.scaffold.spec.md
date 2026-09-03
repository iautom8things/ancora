# Scaffolds and Docs

`mix spec.init`, `mix spec.decision.new`, the `priv/spec_init/` templates,
ancora's own README, and `docs/migration.md`. The content an adopter and
their agents read on day one.

## Intent

specled_ex's templates were the codex defect: most of their content pointed
at retired machinery. Ancora's templates are new writes against content
specs. The agent guide scopes reading to the subjects in play, quotes the
read-protocol constant so template and code cannot drift, says plainly that
there is no generated state, and tells a fresh adopter that the first red is
expected and how to clear it.

```yaml spec-meta
id: ancora.scaffold
kind: module
status: active
summary: spec.init and spec.decision.new scaffolds, template content, ancora README commitments, and the migration checklist.
decisions:
  - ancora.decision.no_execution_no_state
  - ancora.decision.cli_json_contract
```

## Requirements

```yaml spec-requirements
- id: ancora.scaffold.init_writes_templates
  statement: >-
    `mix spec.init` shall write `.spec/AGENTS.md`, `.spec/agents/SKILL.md`,
    `.spec/README.md`, `.spec/config.yml`, `.spec/decisions/README.md`, and
    one seed subject under `.spec/specs/`, printing `wrote` or `kept` per
    file and `spec.init scaffolded <dir>`. `--force` shall overwrite. No
    GitHub workflow file shall be scaffolded.
  priority: must
  stability: stable
- id: ancora.scaffold.agents_md_content
  statement: >-
    The scaffolded AGENTS.md shall, in order: instruct agents to read only
    the subjects named by `spec.next` or the task's `Advances:` field and
    never the whole corpus; quote `Ancora.Output.read_protocol/0` verbatim;
    contain a section stating there is no generated state; teach `mix
    spec.prime --base HEAD` as the session-start idiom and `--base HEAD` for
    day one and for repos with no remote; and state that the fresh scaffold's
    first `spec.check` is expected to fail with `derived/unanchored_subject`
    and that tagging tests clears it.
  priority: must
  stability: evolving
- id: ancora.scaffold.skill_md_content
  statement: >-
    The scaffolded SKILL.md shall contain a triage table of every registry
    code grouped by family with default severities; the acknowledgment rule
    for clearing drift, growth, and shrink; the `Spec-Ack:` grammar with mass
    mechanical edits as its intended use; and the per-subject `overrides:`
    construct with its required `reason`.
  priority: must
  stability: evolving
- id: ancora.scaffold.config_template
  statement: >-
    The scaffolded config.yml shall carry the v1 schema with taught
    defaults, guidance on `default_base` for repos whose trunk is not
    `origin/main`, and one commented `overrides:` example with a reason.
  priority: must
  stability: stable
- id: ancora.scaffold.no_retired_vocabulary
  statement: >-
    No scaffolded template, README, or doc shall mention `execute:`,
    `realized_by:`, `--no-run-commands`, `--accept-drift`, `state.json`,
    `realization_hashes.json`, `Spec-Drift:`, `SPECLED_`, or any retired
    finding code. The test shall read these needles from one shared
    retired-vocabulary list sourced from the migration map.
  priority: must
  stability: stable
- id: ancora.scaffold.fresh_adopter_round_trip
  statement: >-
    Running `mix spec.init` in a tmp git repo and then `mix spec.check --base
    HEAD` through the real Mix task subprocess shall yield
    `derived/unanchored_subject` for the seed subject and verdict `result=fail
    tier=branch`; tagging one test for the seed subject, committing the
    scaffold and anchor, and re-running shall yield `result=pass`.
  priority: must
  stability: stable
- id: ancora.scaffold.decision_new
  statement: >-
    `mix spec.decision.new DECISION_ID` shall write
    `.spec/decisions/<id>.md` with frontmatter `id`, `status`, `date`, and
    `affects:` and the three sections Context, Decision, Consequences,
    printing `spec.decision.new wrote <path>`. The template shall not contain
    `change_type`.
  priority: must
  stability: stable
- id: ancora.scaffold.readme_commitments
  statement: >-
    Ancora's README shall name `Ancora.Parser.parse_file/2`,
    `Ancora.DecisionParser.parse_file/2`, `Ancora.check/2`, and
    `Ancora.validate/2` as the only semver-stable API, state
    that `--root` is an internal affordance outside that commitment, state
    the introspection posture (the tool loads its own dependencies' bytecode
    for export lookup; this is toolchain introspection, not project
    execution), name `mix format --migrate` as an expect-acknowledgment case,
    carry a six-line CI job snippet, and describe the tool as traceability
    and drift detection, never as proof or verified behavior.
  priority: must
  stability: evolving
- id: ancora.scaffold.migration_doc
  statement: >-
    `docs/migration.md` shall carry the consumer migration checklist and the
    complete specled_ex-code to ancora-code map, with the registry count
    matching `Ancora.Finding`.
  priority: must
  stability: evolving
```

## Scenarios

```yaml spec-scenarios
- id: ancora.scaffold.scenario.init_in_tmp_repo
  given:
    - an empty tmp git repository
  when:
    - `mix spec.init --root <tmp>` runs
  then:
    - AGENTS.md, agents/SKILL.md, README.md, config.yml, decisions/README.md, and one seed spec exist under `.spec/`
    - no file under `.github/` is written
    - stdout lists each file as `wrote` and ends with `spec.init scaffolded`
  covers:
    - ancora.scaffold.init_writes_templates
- id: ancora.scaffold.scenario.init_keeps_then_forces
  given:
    - a scaffolded `.spec/` with a hand-edited AGENTS.md
  when:
    - `mix spec.init` runs without and then with `--force`
  then:
    - the first run prints `kept` for AGENTS.md and leaves the edit
    - the second run prints `wrote` and replaces it
  covers:
    - ancora.scaffold.init_writes_templates
- id: ancora.scaffold.scenario.agents_needles
  given:
    - the rendered AGENTS.md
  when:
    - needle checks run
  then:
    - it contains the `Advances:` scoping instruction, the exact `Ancora.Output.read_protocol/0` string, a heading about no generated state, `--base HEAD`, and `derived/unanchored_subject`
  covers:
    - ancora.scaffold.agents_md_content
- id: ancora.scaffold.scenario.skill_triage_table
  given:
    - the rendered SKILL.md
  when:
    - every code in Ancora.Finding is searched for
  then:
    - each code appears once in the triage table with its default severity
    - `Spec-Ack:` and `overrides:` both appear
  covers:
    - ancora.scaffold.skill_md_content
- id: ancora.scaffold.scenario.config_template_loads
  given:
    - the rendered config.yml
  when:
    - Ancora.Config loads it
  then:
    - no `config/unknown_key` or `config/invalid_value` fires
    - the file contains a commented `overrides:` block with a `reason`
  covers:
    - ancora.scaffold.config_template
- id: ancora.scaffold.scenario.retired_vocabulary_absent
  given:
    - every rendered template, the README, and docs/migration.md outside its code-map table
  when:
    - the shared retired-vocabulary list is grepped
  then:
    - zero hits
  covers:
    - ancora.scaffold.no_retired_vocabulary
- id: ancora.scaffold.scenario.fresh_adopter_journey
  given:
    - a tmp git repo scaffolded by `mix spec.init`
  when:
    - the real `mix spec.check --base HEAD` task runs as a subprocess
    - one test is tagged for the seed subject and the scaffold and anchor are committed
    - the real check runs again as a subprocess
  then:
    - the first run reports `derived/unanchored_subject` and `result=fail tier=branch`
    - the second run reports `result=pass`
  covers:
    - ancora.scaffold.fresh_adopter_round_trip
- id: ancora.scaffold.scenario.decision_new_shape
  given:
    - `mix spec.decision.new myapp.decision.example --title "Example"`
  when:
    - the task runs
  then:
    - the written file has frontmatter id/status/date/affects and three section headings
    - the file does not contain `change_type`
  covers:
    - ancora.scaffold.decision_new
- id: ancora.scaffold.scenario.readme_needles
  given:
    - ancora's README
  when:
    - needle checks run
  then:
    - it names all four stable functions, says `--root` is internal, contains the introspection paragraph, mentions `mix format --migrate`, and contains no occurrence of "proof" or "verified behavior"
  covers:
    - ancora.scaffold.readme_commitments
- id: ancora.scaffold.scenario.migration_map_complete
  given:
    - `docs/migration.md`
  when:
    - its code-map table is parsed
  then:
    - every ancora code it names exists in Ancora.Finding
    - the stated registry count equals the registry size
  covers:
    - ancora.scaffold.migration_doc
```

## Verification

```yaml spec-verification
- kind: tagged_tests
  covers:
    - ancora.scaffold.init_writes_templates
    - ancora.scaffold.agents_md_content
    - ancora.scaffold.skill_md_content
    - ancora.scaffold.config_template
    - ancora.scaffold.no_retired_vocabulary
    - ancora.scaffold.fresh_adopter_round_trip
    - ancora.scaffold.decision_new
    - ancora.scaffold.readme_commitments
    - ancora.scaffold.migration_doc
```
