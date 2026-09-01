# Review Artifact

`mix spec.review`: the HTML artifact CI renders per PR, its views, the
derived-set grouping of the Code pivot, the pure-Elixir markdown transform,
and the stdout meta line the shared workflow greps.

## Intent

The artifact is how a human reviews a spec-bearing PR. It keeps the approved
master-detail chassis, drops the coverage and realization chrome, and
organizes code changes by what the subject's tests actually call. Markdown
rendering is owned code over earmark_parser's AST so the package has zero
native dependencies and the escape posture is testable directly.

Modules: `Ancora.Review`, `Ancora.Review.Html`, `Ancora.Review.FileDiff`,
`Ancora.Review.SpecDiff`, `Ancora.Review.FindingsDelta`, `Ancora.Markdown`.

```yaml spec-meta
id: ancora.review
kind: module
status: active
summary: The spec.review HTML artifact, derived-set Code grouping, owned markdown transform, and byte-stable meta line.
```

## Requirements

```yaml spec-requirements
- id: ancora.review.views
  statement: >-
    The artifact shall render a master-detail layout whose left rail lists
    Overview, Decisions changed, affected subjects, an outside-the-spec-system
    panel, all files, and Spec health, and whose per-subject detail offers
    exactly three pivots: Spec, Code, and Decisions. No Coverage pivot,
    triangle diagram, or verification-strength chrome shall render.
  priority: must
  stability: evolving
- id: ancora.review.code_pivot_grouping
  statement: >-
    The Code pivot shall group a subject's changes into three sections:
    watched interface (one card per derived binding whose body changed, with
    `M.f/a`, a drift or acknowledged badge, the clause-level hunk, and a
    defining-file link), supporting changes (remaining hunks in footprint
    files), and test changes (tagged-test diffs plus the growth and shrink
    delta as added and removed binding lists).
  priority: must
  stability: evolving
- id: ancora.review.findings_inline
  statement: >-
    Each subject card shall carry this change's `derived/*` findings as
    badges with expandable detail, and the page shall render a verdict chip
    reflecting the gate outcome and a triage panel listing findings by
    severity.
  priority: must
  stability: evolving
- id: ancora.review.findings_delta_without_store
  statement: >-
    Repo-state findings shall be computed once against the base-side corpus
    materialized by Ancora.BaseView and once against HEAD, then diffed into
    introduced, pre-existing, and resolved. Diff-scoped findings shall be
    listed as introduced by construction. No evidence store or persisted
    snapshot shall be read or written.
  priority: must
  stability: stable
- id: ancora.review.markdown_transform
  statement: >-
    Ancora.Markdown shall render ADR and spec prose by transforming
    `EarmarkParser.as_ast/2` output (GFM tables enabled) with an owned
    recursive renderer. Raw HTML nodes shall render escaped and inert, a
    render failure shall degrade to escaped source, and `[[id]]` wikilinks
    shall resolve to in-page anchors.
  priority: must
  stability: stable
- id: ancora.review.meta_line_shape
  statement: >-
    `mix spec.review` shall print exactly `spec.review wrote <path> (<bytes>
    bytes)` followed by one indented line `base=<ref> head=<ref>
    affected_subjects=<N> findings=<N>`, byte-compatible with the line the
    shared CI workflow greps today.
  priority: must
  stability: stable
- id: ancora.review.prism_carried
  statement: >-
    Prism.js shall ship vendored under `priv/spec_review_assets/` with its
    MIT license header intact and a NOTICE entry, trimmed to the grammars
    elixir, erlang, diff, yaml, markdown, json, html, css, and javascript.
  priority: must
  stability: stable
- id: ancora.review.size_budget
  statement: >-
    The HTML rendering subsystem (`lib/ancora/review/*.ex` plus
    `lib/ancora/markdown.ex`) shall total at most 5,000 lines with no single
    module over 2,500, enforced by a standing test. If the budget is
    exceeded, the first cuts are, in order: supporting-changes hunks degrade
    to a file-link list; findings delta degrades to HEAD-side repo-state
    findings only. The verdict chip and triage panel are not cuttable.
  priority: must
  stability: evolving
- id: ancora.review.output_flag
  statement: >-
    `--output` shall write the artifact to the given path (default
    `_build/spec_review.html`) and `--open` shall open it; the artifact is a
    render target, not derived state.
  priority: must
  stability: stable
```

## Scenarios

```yaml spec-scenarios
- id: ancora.review.scenario.clean_diff_renders_green_chip
  given:
    - a fixture with an empty change set
  when:
    - the artifact is rendered
  then:
    - the verdict chip shows pass
    - the three pivots are present and no Coverage pivot exists
  covers:
    - ancora.review.views
    - ancora.review.findings_inline
- id: ancora.review.scenario.drift_card_in_watched_interface
  given:
    - a subject whose watched `Billing.next/1` body changed without acknowledgment
  when:
    - the Code pivot is rendered
  then:
    - a card under watched interface names `Billing.next/1` with a drift badge and the hunk
    - the subject card carries a `derived/drift` badge
  covers:
    - ancora.review.code_pivot_grouping
    - ancora.review.findings_inline
- id: ancora.review.scenario.growth_listed_under_test_changes
  given:
    - a subject whose tests newly call `Billing.void/2`
  when:
    - the Code pivot is rendered
  then:
    - test changes lists `Billing.void/2` as added
  covers:
    - ancora.review.code_pivot_grouping
- id: ancora.review.scenario.findings_delta_categories
  given:
    - a base corpus with one `spec/unknown_reference` and a HEAD corpus that fixes it and adds one `adr/affects_empty`
  when:
    - the findings delta is computed
  then:
    - the unknown reference is resolved, the affects_empty is introduced, and nothing is pre-existing
  covers:
    - ancora.review.findings_delta_without_store
- id: ancora.review.scenario.raw_html_escaped
  given:
    - an ADR whose Context contains `<script>alert(1)</script>`
  when:
    - the artifact is rendered
  then:
    - the output contains the escaped text and no executable script element
  covers:
    - ancora.review.markdown_transform
- id: ancora.review.scenario.render_failure_degrades
  given:
    - prose that makes the renderer raise
  when:
    - the artifact is rendered
  then:
    - the section shows the escaped source and the task still writes the artifact
  covers:
    - ancora.review.markdown_transform
- id: ancora.review.scenario.meta_line_golden
  given:
    - any successful `mix spec.review` run
  when:
    - stdout is captured
  then:
    - line one matches `spec.review wrote <path> (<bytes> bytes)` and line two matches the indented base/head/affected_subjects/findings shape
  covers:
    - ancora.review.meta_line_shape
- id: ancora.review.scenario.prism_license_present
  given:
    - the vendored Prism.js file
  when:
    - its header is read
  then:
    - the MIT license header is present and NOTICE names Prism.js
  covers:
    - ancora.review.prism_carried
- id: ancora.review.scenario.line_budget_test
  given:
    - the files `lib/ancora/review/*.ex` and `lib/ancora/markdown.ex`
  when:
    - their line counts are summed
  then:
    - the total is at most 5000 and no file exceeds 2500
  covers:
    - ancora.review.size_budget
- id: ancora.review.scenario.output_path
  given:
    - `mix spec.review --output tmp/r.html`
  when:
    - the task runs
  then:
    - `tmp/r.html` exists and the meta line names it
  covers:
    - ancora.review.output_flag
```

## Verification

```yaml spec-verification
- kind: tagged_tests
  covers:
    - ancora.review.views
    - ancora.review.code_pivot_grouping
    - ancora.review.findings_inline
    - ancora.review.findings_delta_without_store
    - ancora.review.markdown_transform
    - ancora.review.meta_line_shape
    - ancora.review.prism_carried
    - ancora.review.size_budget
    - ancora.review.output_flag
```
