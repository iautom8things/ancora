# Migrating from spec_led_ex

This checklist is for the Argos, Engage, Builder, and Atlas migration PRs. Do
the steps in one PR so configuration, spec edits, and CI agree on the same
Ancora version.

## Checklist

1. Replace the dependency with the pinned Ancora release and refresh the lock
   file.
2. Run `mix spec.init`, then compare the generated agent guide, skill, README,
   and configuration with the repository's existing `.spec/` files. Keep
   repository-specific instructions.
3. Move authored subjects to `.spec/specs/` and decisions to
   `.spec/decisions/`. Remove fields and verification kinds that Ancora no
   longer reads.
4. Tag tests with each requirement ID. A tagged test must call the production
   function that anchors its subject.
5. Set `default_base`, `test_paths`, and `lib_paths` for the repository. Treat
   `default_base` as a local-development convenience. Copy severity choices
   through the code map below. Every subject override needs a reason.
6. Replace the old CI command with `mix spec.check --base origin/main`, using
   the repository's actual trunk ref when it differs. CI must always pass
   `--base` explicitly.
7. Run `mix spec.check --base HEAD` once to fix corpus and tag errors. Then run
   against the trunk base and review every drift, growth, shrink, and uncovered
   file finding.
8. Remove the compatibility shim only after the repository's CI passes with
   Ancora alone.

Engage and Builder must review accepted ADRs during their next Ancora upgrade.
An ADR whose `affects:` lists only a subject no longer authorizes deleting or
downgrading every requirement in that subject. Add each exact requirement id
that the ADR is meant to authorize. Subject ids remain valid when they only
document the ADR's broader scope.

Use `retires:` when an accepted ADR removes a requirement or whole subject from
the corpus. Repeat each retired id in `affects:` and `retires:`. Cold validation
then accepts the missing id, and the append-only guard accepts deletion of the
named requirement or every requirement under the named subject. `retires:` does
not authorize a `must` to `should` downgrade.

When upgrading, Engage should remove its `adr/affects_unresolved: info`
demotion and return to the registry default. Builder should replace its six
identifier tombstone files with `retires:` entries, then delete the tombstones
and their `derived/unanchored_subject` overrides.

## Finding code map

Ancora has 30 finding codes. The middle column is the closed registry. Several
old checks converge on one current code, while some current codes have no
direct predecessor.

| specled_ex code | Ancora code | Default severity |
|---|---|---|
| `branch_guard_realization_drift` | `derived/drift` | `error` |
| no direct predecessor | `derived/growth` | `warning` |
| no direct predecessor | `derived/shrink` | `warning` |
| `detector_unavailable` | `derived/unresolved_calls` | `info` |
| `detector_unavailable` | `derived/unparseable_source` | `error` |
| `branch_guard_dangling_binding` | `derived/unanchored_subject` | `warning` |
| `branch_guard_unmapped_change` | `change/uncovered_file` | `warning` |
| `branch_guard_missing_decision_update` | `change/missing_decision` | `warning` |
| `branch_guard_requirement_without_test_tag` | `tags/new_requirement_untagged` | `warning` |
| `tag_scan_parse_error` | `tags/parse_error` | `error` |
| `tag_dynamic_value_skipped` | `tags/dynamic_value` | `info` |
| `requirement_without_test_tag` | `tags/requirement_untagged` | `info` |
| `verification_cover_untagged` | `tags/unknown_requirement` | `warning` |
| `append_only/requirement_deleted` | `append/requirement_deleted` | `error` |
| `append_only/must_downgraded` | `append/must_downgraded` | `error` |
| `verification_kind_invalid`, `verification_unknown_kind` | `format/retired_construct` | `warning` |
| `verification_command_*`, `tagged_tests_cover_not_executed` | `spec/parse_error` | `error` |
| `duplicate_requirement_id`, `duplicate_scenario_id`, `duplicate_subject_id`, `duplicate_exception_id`, `duplicate_decision_id` | `spec/duplicate_id` | `error` |
| `invalid_id_format` | `spec/invalid_id` | `error` |
| `meta_field_missing`, `requirement_id_missing`, `scenario_id_missing` | `spec/missing_field` | `error` |
| `verification_target_missing*`, `surface_target_*`, `scenario_cover_unknown`, `subject_unknown_decision_reference` | `spec/unknown_reference` | `error` |
| `requirement_missing_verification` | `spec/requirement_unverified` | `info` |
| `decision_*` parse checks | `adr/parse_error` | `error` |
| `decision_*` section checks | `adr/missing_section` | `error` |
| `cross_field/affects_empty` | `adr/affects_empty` | `warning` |
| `cross_field/affects_unresolved` | `adr/affects_unresolved` | `error` |
| `overlap/duplicate_covers` | `overlap/duplicate_covers` | `error` |
| `overlap/must_stem_collision` | `overlap/must_stem_collision` | `error` |
| legacy configuration key checks | `config/unknown_key` | `warning` |
| legacy configuration value checks | `config/invalid_value` | `warning` |

The old trailer and environment settings map as follows:

| Old setting | Ancora setting |
|---|---|
| `Spec-Drift:` | `Spec-Ack: <code>=<info\|warning>` |
| `SPECLED_SHOW_INFO` | `ANCORA_SHOW_INFO` |
| `SPECLED_COMMAND_OUTPUT_DIR`, `SPECLED_DISABLE_TRACER` | removed |
