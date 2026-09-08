---
name: spec-led-development
description: Maintain this repository's ancora specs, decisions, and test anchors.
---

# Spec-led development

Read only the subjects named by `mix spec.next` or the task's `Advances:` field.
Treat `must` requirements as contracts and scenarios as behavior to cover with
tagged tests.

## Finding triage

| Family | Code | Default |
|---|---|---|
| derived | `derived/drift` | error |
| derived | `derived/drift_transitive` | info |
| derived | `derived/growth` | warning |
| derived | `derived/shrink` | warning |
| derived | `derived/growth_transitive` | info |
| derived | `derived/shrink_transitive` | info |
| derived | `derived/unresolved_calls` | info |
| derived | `derived/unparseable_source` | error |
| derived | `derived/unanchored_subject` | warning |
| change | `change/uncovered_file` | warning |
| change | `change/missing_decision` | warning |
| tags | `tags/new_requirement_untagged` | warning |
| tags | `tags/tag_borrowed` | info |
| tags | `tags/parse_error` | error |
| tags | `tags/dynamic_value` | info |
| tags | `tags/requirement_untagged` | info |
| tags | `tags/unknown_requirement` | warning |
| append | `append/requirement_deleted` | error |
| append | `append/must_downgraded` | error |
| append | `append/statement_changed` | info |
| format | `format/retired_construct` | warning |
| spec | `spec/parse_error` | error |
| spec | `spec/duplicate_id` | error |
| spec | `spec/invalid_id` | error |
| spec | `spec/missing_field` | error |
| spec | `spec/unknown_reference` | error |
| spec | `spec/requirement_unverified` | info |
| adr | `adr/parse_error` | error |
| adr | `adr/missing_section` | error |
| adr | `adr/affects_empty` | warning |
| adr | `adr/affects_unresolved` | error |
| overlap | `overlap/duplicate_covers` | error |
| overlap | `overlap/must_stem_collision` | error |
| config | `config/unknown_key` | warning |
| config | `config/invalid_value` | warning |

Edit the affected subject's requirement or scenario when drift, growth, or
shrink reflects an intentional contract change. Restore the code or test when
it does not.

For a mass mechanical edit that does not change the contract, add a commit
trailer in this form:

```text
Spec-Ack: <code>=<info|warning>
```

The trailer only lowers severity. Reviewers should be able to tell why the
edit is mechanical from the diff and commit message.

Run `mix spec.check --verbose` to list all info findings. Use
`--explain-acks` to list findings whose severity came from config, a trailer,
or an acknowledgment. `derived/drift_transitive` means a changed derived
binding is outside the subject's declared `surface:`. `tags/tag_borrowed`
means a new test tag points at an unchanged requirement.
`append/statement_changed` means requirement text changed.

A subject may declare `surface:` as a nonempty list of exact repo-relative
source paths. `surface: []`, globs, absolute paths and traversal are rejected.
Observed drift, additions and removals outside the list produce informational
`derived/drift_transitive`, `derived/growth_transitive` and
`derived/shrink_transitive` findings. Omitting the field keeps primary checks.
When both sides declare ownership, either side can keep a change primary;
first introduction and later ownership edits appear in review as policy changes.
Surface never claims coverage or unchanged behavior.

Use a subject-specific override only when a standing repository constraint
cannot be expressed through a tagged test. Every override requires a reason.
An optional `requirement:` line narrows it to one requirement id.

```yaml
overrides:
  - subject: project.core
    # requirement: project.core.invoice_totals
    code: derived/unanchored_subject
    severity: info
    reason: Covered by an external integration suite.
```

Ancora attributes calls to each tagged test, its applicable setup and reachable
test helpers. Neighboring tests and unused helpers do not contribute bindings.
Inspect the reported callsite chain before editing a contract. An unresolved
call is an analysis limitation, not evidence that a contract was removed.
Do not add cosmetic requirements or split tests just to clear a finding.

For infrastructure without a statically observable test call, use an exact,
reasoned exception. The file remains excepted rather than covered:

```yaml
overrides:
  - file: lib/my_app_web/router.ex
    code: change/uncovered_file
    severity: info
    reason: Exercised through the Phoenix request pipeline.
```

File exceptions accept only `info`, require a reason, and cannot combine with
`subject:` or `requirement:`. Subject overrides prefer a matching `requirement:`
over the subject default; duplicate selectors are rejected regardless of order.
