---
id: ancora.decision.review_artifact_contract
status: accepted
date: 2026-09-03
affects:
  - ancora.review
  - ancora.review.views
  - ancora.review.view_model_builder
  - ancora.review.code_pivot_grouping
  - ancora.review.findings_inline
  - ancora.review.findings_delta_without_store
  - ancora.review.markdown_transform
  - ancora.review.meta_line_shape
  - ancora.review.prism_carried
  - ancora.review.size_budget
  - ancora.review.output_flag
---

# Review artifact contract follows the shipped boundaries

## Context

The review subject was drafted before its implementation landed. It named the
intended layout, but it did not contract the public builder, classifier,
markdown, HTML, and Mix task entry points that the tagged tests now call. It
also described watched cards as clause-level hunks. The implementation renders
the changed file's diff on each watched card. Sending every remaining changed
source file to every affected subject made the artifact grow with the product
of subjects and files, and repeated its `file-*` anchors.

## Decision

The contract follows the boundaries in the shipped implementation.
`Ancora.Review.build/2` assembles the root-and-base view model,
`Ancora.Review.FindingsDelta.classify/2` and `classify/3` classify findings,
`Ancora.Markdown.render/1` and `render/2` transform prose,
`Ancora.Review.Html.render/1` returns the self-contained document, and
`Mix.Tasks.Spec.Review.run/1` writes that document and prints the CI metadata.
The Code pivot describes full changed-file diffs for watched cards and the
remaining changed files in each subject's derived footprint as supporting
changes. Each changed file's diff body appears at most once under its
deterministic owning subject and once in All files. Other watched cards retain
their badge and defining-file link without repeating the diff. The All files
article owns the file's single `file-*` anchor, which every watched card links
to. A 200-file standing fixture bounds the rendered artifact below 1 MB. The
artifact remains a render target and no review state persists between runs.
Authored diff-line markup remains outside Prism highlighting so scripts cannot
replace its add, delete, and hunk spans. The artifact also exposes finding
severity in text and with a visible marker, names the finding file, and avoids
claiming ARIA tab semantics that its pivot controls do not implement.

## Consequences

Tagged tests anchor each public entry point to a falsifiable requirement and
scenario. Future changes to these boundaries require a matching review-subject
edit. Watched cards can repeat context outside the changed clause, but they do
not repeat a changed file's diff body. Supporting changes are limited to the
tagged tests and defining files in the subject's derived footprint. Prism CSS
loads before the artifact's CSS so the artifact controls diff presentation in
both colour schemes.
