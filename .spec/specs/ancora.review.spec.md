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
`Ancora.Review.SpecDiff`, `Ancora.Review.FindingsDelta`,
`Ancora.Review.GateCache`, `Ancora.Markdown`.

```yaml spec-meta
id: ancora.review
kind: module
status: active
summary: The spec.review HTML artifact, derived-set Code grouping, owned markdown transform, and byte-stable meta line.
decisions:
  - ancora.decision.adopter_attribution
  - ancora.decision.field_friction_response
  - ancora.decision.review_artifact_contract
  - ancora.decision.local_review_handoff
```

## Requirements

```yaml spec-requirements
- id: ancora.review.views
  statement: >-
    Ancora.Review.Html.render/1 shall turn a review view model into one
    self-contained HTML document with a master-detail layout. Its left rail
    shall link Overview, Decisions changed, affected subjects, Outside the
    spec system, All files, and Spec health. Each subject shall offer exactly
    three pivots: Spec, Code, and Decisions. No Coverage pivot, triangle
    diagram, verification-strength chrome, or incomplete ARIA tab semantics
    shall render. The document title shall include the head ref, the overview
    shall include its generation timestamp, and long code shall wrap.
  priority: must
  stability: evolving
- id: ancora.review.view_model_builder
  statement: >-
    Ancora.Review.build/2 shall build from the requested repository root and
    base ref and return `{:ok, view}`. For each affected subject, the view
    shall combine its contract, tagged test files, changed-file diffs, and
    gate findings so newly called functions appear in `added_bindings` and
    changed watched functions appear as primary drift, transitive drift, or
    acknowledged cards. The builder shall pass its already-parsed base and HEAD subjects to
    `Ancora.Review.SpecDiff.compute/2`; no root-reading `compute/3` entry point
    shall exist.
    The selected workspace shall use the same normalized path and config as
    the gate. Diffs for nested Mix projects shall use project-relative file
    paths. Diff generation shall disable external diff drivers and textconv
    commands so reviewing a project does not run its configured programs.
    File diffs shall preserve complete tracked and untracked path identities,
    including whitespace, Unicode, quotes, backslashes, and control characters.
  priority: must
  stability: evolving
- id: ancora.review.code_pivot_grouping
  statement: >-
    The Code pivot shall group a subject's changes into three sections:
    watched interface (one card per derived binding whose body changed, with
    `M.f/a`, a drift, drift_transitive, or acknowledged badge, the changed
    file's diff, and a defining-file link), supporting changes (remaining changed source-file
    diffs), and test changes (tagged-test diffs plus growth and shrink
    bindings listed as added and removed). Watched badges shall use the badge
    value as their CSS class. Transitive drift shall use the info color, and
    only findings with severity source ack shall produce acknowledged cards.
    Each defining-file link shall target the one
    `file-*` anchor for that file in All files. Diff code shall remain outside
    Prism highlighting, preserve authored per-line spans, and apply review CSS
    after Prism CSS.
  priority: must
  stability: evolving
- id: ancora.review.findings_inline
  statement: >-
    Each subject card shall carry this change's `derived/*` findings as
    badges with expandable detail, and the page shall render a verdict chip
    containing the gate verdict from the same run and a triage panel listing
    findings by severity. Info-only findings shall leave both the gate and
    chip passing. Each finding summary shall display its severity, file, and
    a visible marker so colour is not the only severity indicator.
  priority: must
  stability: evolving
- id: ancora.review.findings_delta_without_store
  statement: >-
    FindingsDelta shall classify introduced, pre-existing and resolved repository
    findings plus diff findings without stored state. Review shall reuse Gate's
    resolved HEAD findings and resolve base repository findings with base config
    from the selected workspace, without applying HEAD trailers to the base. Finding
    identity shall exclude severity. Config or trailer changes, including off,
    shall appear as policy changes rather than repaired defects. Current-state
    counts, severity sources and verdict shall agree with the gate for the same
    run. Ownership declaration changes shall be displayed separately.
  priority: must
  stability: stable
- id: ancora.review.reuses_check_result
  statement: >-
    `mix spec.check` shall store the gate fields review reads (all findings,
    checked counts, errors, warnings, fail and review data) at
    `_build/ancora/gate.etf` through Ancora.Review.GateCache, and only when git
    ignores that path. The stored key shall cover ancora's module checksums and
    dependency versions, the Elixir and OTP versions, the root, the spec
    directory, the base and HEAD commit ids, and the content of every dirty or
    untracked file and of every ignored file under the spec, test and library
    paths. Check shall compute the key before and after its gate run and store
    nothing when they differ. `mix spec.review` shall use the stored fields only
    on an exact key match and shall rerun the gate on any miss, including a
    missing, truncated or malformed file. Check shall never read the file, a
    failed write shall not change its output or exit status, and its returned
    report shall carry no review data.
  priority: must
  stability: evolving
- id: ancora.review.markdown_transform
  statement: >-
    Ancora.Markdown.render/1 shall render ADR and spec prose by transforming
    `EarmarkParser.as_ast/2` output with GFM tables enabled through an owned
    recursive renderer. Ancora.Markdown.render/2 shall accept an injected
    renderer for the same parsed AST. Both arities shall return a binary;
    raw HTML nodes shall render escaped and inert, `[[id]]` wikilinks shall
    resolve to in-page anchors, and any parse or renderer failure shall
    return the escaped source inside a fallback block.
  priority: must
  stability: stable
- id: ancora.review.meta_line_shape
  statement: >-
    On success, Mix.Tasks.Spec.Review.run/1 shall print exactly `spec.review
    wrote <path> (<bytes> bytes)` followed by one indented line `base=<ref>
    head=<ref> affected_subjects=<N> findings=<N>`, byte-compatible with the
    line the shared CI workflow greps today. A usage failure shall raise
    without printing any `result=` line. An invalid `--spec-dir` workspace
    shall print the environment message and exit 1 without a verdict or stack
    trace.
  priority: must
  stability: stable
- id: ancora.review.prism_carried
  statement: >-
    Prism.js shall ship vendored under `priv/spec_review_assets/` with its
    MIT license header intact and a NOTICE entry, and its grammar set
    trimmed to elixir, erlang, diff, yaml, markdown, json, markup, css,
    javascript, and clike. A standing test shall pin the SHA-256 digest of
    all ten files and derive that grammar list from the vendored filenames,
    so neither NOTICE nor this statement can drift from what ships.
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
- id: ancora.review.artifact_size
  statement: >-
    The rendered artifact shall include each changed file's diff body at most
    twice: once under the single subject that owns the file and once in All
    files. Every `file-*` anchor shall be unique, and every defining-file link
    shall target that anchor. A standing 200-file fixture shall render to less
    than 1 MB.
  priority: must
  stability: evolving
- id: ancora.review.output_flag
  statement: >-
    Mix.Tasks.Spec.Review.run/1 shall resolve a relative `--output` path from
    the requested root, create its parent directories, and write the binary
    returned by Ancora.Review.Html.render/1. The default path shall be
    `_build/spec_review.html`; `--open` shall ask the host to open the written
    file without turning a launcher failure into a task failure. The artifact
    is a render target, not derived state.
  priority: must
  stability: stable
```

## Scenarios

```yaml spec-scenarios
- id: ancora.review.scenario.html_view_renders_green_chip
  given:
    - a complete review view model with a pass verdict and one affected subject
  when:
    - Ancora.Review.Html.render/1 renders the model
  then:
    - the verdict chip shows pass
    - the left-rail links and triage panel are present
    - the three pivots are present and no Coverage pivot exists
    - the title names the head ref and the overview names the generation timestamp
    - the pivot controls do not claim an incomplete ARIA tab contract
    - long code can wrap
  covers:
    - ancora.review.views
    - ancora.review.findings_inline
- id: ancora.review.scenario.drift_card_in_watched_interface
  given:
    - a temporary repository whose tagged test calls `Billing.next/1`
    - on HEAD the watched function body changes without a subject contract edit
  when:
    - Ancora.Review.build/2 builds the view and Ancora.Review.Html.render/1 renders its Code pivot
  then:
    - a card under watched interface names `Billing.next/1` with a drift badge and the hunk
    - the subject card carries a `derived/drift` badge
    - Prism does not rewrite the authored add and delete spans in the browser
    - only direct diff line spans render as blocks and review CSS wins over Prism CSS
  covers:
    - ancora.review.view_model_builder
    - ancora.review.code_pivot_grouping
    - ancora.review.findings_inline
- id: ancora.review.scenario.transitive_drift_badge
  given:
    - a changed derived binding whose defining file is outside the subject's declared `surface:`
  when:
    - the review artifact builds and renders its watched interface
  then:
    - the binding renders once with a `drift_transitive` badge
    - the binding does not render as acknowledged
  covers:
    - ancora.review.view_model_builder
    - ancora.review.code_pivot_grouping
- id: ancora.review.scenario.growth_listed_under_test_changes
  given:
    - a temporary repository whose tagged test calls `Billing.next/1` at the base ref
    - on HEAD the tagged test also calls `Billing.void/2`
  when:
    - Ancora.Review.build/2 builds the view and Ancora.Review.Html.render/1 renders its Code pivot
  then:
    - the affected subject's `added_bindings` is `Billing.void/2`
    - test changes lists `Billing.void/2` as added
  covers:
    - ancora.review.view_model_builder
    - ancora.review.code_pivot_grouping
- id: ancora.review.scenario.acknowledged_body_change
  given:
    - a tagged test that calls `Billing.next/1`
    - both the function body and its subject requirement change after the base ref
  when:
    - Ancora.Review.build/2 builds the view
  then:
    - watched interface contains a `Billing.next/1` card with an acknowledged badge
    - the badge's CSS class is acknowledged rather than error
  covers:
    - ancora.review.view_model_builder
    - ancora.review.code_pivot_grouping
- id: ancora.review.scenario.findings_delta_categories
  given:
    - a base corpus with one `spec/unknown_reference` and a HEAD corpus that fixes it and adds one `adr/affects_empty`
    - one `derived/growth` diff-scoped finding
  when:
    - Ancora.Review.FindingsDelta.classify/3 classifies the three lists
  then:
    - the unknown reference is resolved
    - the affects_empty and growth findings are introduced
    - an identity present on both sides is pre-existing and does not appear as introduced
  covers:
    - ancora.review.findings_delta_without_store
- id: ancora.review.scenario.verdict_chip_matches_gate
  given:
    - a temporary repository whose only introduced finding is `spec/requirement_unverified` at info severity
  when:
    - `mix spec.check` and `mix spec.review` run from the same commit against the same base
  then:
    - the gate passes and the rendered artifact's verdict chip shows pass
    - promoting that introduced finding to error makes the gate and rendered chip both show fail
  covers:
    - ancora.review.findings_inline
- id: ancora.review.scenario.stable_findings_are_clean
  given:
    - identical repo-state finding lists for the base and HEAD sides
  when:
    - Ancora.Review.FindingsDelta.classify/2 classifies them
  then:
    - the findings are pre-existing and the change verdict is clean
  covers:
    - ancora.review.findings_delta_without_store
- id: ancora.review.scenario.raw_html_escaped
  given:
    - an ADR whose Context contains `<script>alert(1)</script>`
  when:
    - Ancora.Markdown.render/1 renders the Context
  then:
    - the output contains the escaped text and no executable script element
  covers:
    - ancora.review.markdown_transform
- id: ancora.review.scenario.gfm_and_wikilinks_render
  given:
    - a GFM table containing `[[billing.invoice]]`
  when:
    - Ancora.Markdown.render/1 renders the prose
  then:
    - the result contains a table and an in-page link to `billing.invoice`
  covers:
    - ancora.review.markdown_transform
- id: ancora.review.scenario.render_failure_degrades
  given:
    - unsafe prose and an injected renderer that raises
  when:
    - Ancora.Markdown.render/2 renders the prose
  then:
    - the result is a fallback block containing escaped source and no raw HTML element
  covers:
    - ancora.review.markdown_transform
- id: ancora.review.scenario.meta_line_golden
  given:
    - a temporary repository and a relative output path
  when:
    - Mix.Tasks.Spec.Review.run/1 succeeds with stdout captured
  then:
    - line one matches `spec.review wrote <path> (<bytes> bytes)` and line two matches the indented base/head/affected_subjects/findings shape
  covers:
    - ancora.review.meta_line_shape
- id: ancora.review.scenario.prism_license_present
  given:
    - the ten vendored Prism.js files and their reviewed SHA-256 digests
  when:
    - their bytes, the subject requirement, and NOTICE are checked
  then:
    - the MIT license header is present and NOTICE names Prism.js
    - every digest matches the reviewed value
    - NOTICE and the requirement name the same grammar list, derived from the vendored filenames
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
- id: ancora.review.scenario.artifact_file_fanout
  given:
    - a temporary repository with three subjects whose tagged tests call one shared public function
    - the shared function's definition changes after the base ref
  when:
    - Ancora.Review.build/2 builds the view and Ancora.Review.Html.render/1 renders it
  then:
    - the changed definition's diff body appears exactly twice, once under its owning subject and once in All files
    - all three watched cards render with their badges and defining-file links
    - every `file-*` id occurs exactly once
    - all three defining-file links target that unique id
  covers:
    - ancora.review.artifact_size
    - ancora.review.view_model_builder
    - ancora.review.code_pivot_grouping
- id: ancora.review.scenario.artifact_byte_budget
  given:
    - a review view containing 200 changed files with 15 short added lines each
  when:
    - Ancora.Review.Html.render/1 renders the view
  then:
    - the artifact is smaller than 1 MB
  covers:
    - ancora.review.artifact_size
- id: ancora.review.scenario.check_handoff_is_transparent
  given:
    - a repository that ignores `_build` with a drifted binding
  when:
    - Ancora.Review.build/2 runs with no handoff file, after `Ancora.check/2` stored one through its `review_cache` option, after the file is truncated, and after it is overwritten with garbage
  then:
    - all four views are equal apart from their generation time, including the failing verdict
    - a stored file whose findings were emptied under the matching key yields a view with no findings, so the warm path reads the file
  covers:
    - ancora.review.reuses_check_result
- id: ancora.review.scenario.check_handoff_key_moves
  given:
    - a repository that ignores `_build` and `test/scratch_*`
  when:
    - a build artifact or the handoff file appears under `_build`, then a tracked file changes, an untracked file appears, an ignored file appears under a test path, and HEAD moves
  then:
    - the build output leaves the key unchanged and every later step yields a new key
  covers:
    - ancora.review.reuses_check_result
- id: ancora.review.scenario.check_never_reads_handoff
  given:
    - a repository with a drifted binding and a stored handoff file
  when:
    - `mix spec.check` runs as a subprocess with the file warm, with its findings emptied under the matching key, and with the file corrupted
  then:
    - every run prints the same stdout and exits with the same status
    - `Ancora.check/2` returns the same report with and without its `review_cache` option, in plain and JSON mode
  covers:
    - ancora.review.reuses_check_result
- id: ancora.review.scenario.check_handoff_needs_ignored_build
  given:
    - a repository whose tree moved after the key was taken, and a repository whose `.gitignore` un-ignores `_build`
  when:
    - Ancora.Review.GateCache.store/3 runs with the old key, and `Ancora.check/2` runs with its `review_cache` option
  then:
    - no handoff file is written in either case and `git status` stays clean
  covers:
    - ancora.review.reuses_check_result
    - ancora.gate.no_derived_state
- id: ancora.review.scenario.output_path
  given:
    - Mix.Tasks.Spec.Review.run/1 receives `--output tmp/r.html`
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
    - ancora.review.view_model_builder
    - ancora.review.code_pivot_grouping
    - ancora.review.findings_inline
    - ancora.review.findings_delta_without_store
    - ancora.review.markdown_transform
    - ancora.review.meta_line_shape
    - ancora.review.prism_carried
    - ancora.review.size_budget
    - ancora.review.artifact_size
    - ancora.review.output_flag
    - ancora.review.reuses_check_result
```
