---
id: ancora.decision.review_artifact_contract
status: accepted
date: 2026-09-03
affects:
  - ancora.review
---

# Review artifact contract follows the shipped boundaries

## Context

The review subject was drafted before its implementation landed. It named the
intended layout, but it did not contract the public builder, classifier,
markdown, HTML, and Mix task entry points that the tagged tests now call. It
also described watched cards as clause-level hunks and supporting changes as
footprint files. The implementation renders the changed file's diff on each
watched card and treats the remaining changed source files as supporting
changes.

## Decision

The contract follows the boundaries in the shipped implementation.
`Ancora.Review.build/2` assembles the root-and-base view model,
`Ancora.Review.FindingsDelta.classify/2` and `classify/3` classify findings,
`Ancora.Markdown.render/1` and `render/2` transform prose,
`Ancora.Review.Html.render/1` returns the self-contained document, and
`Mix.Tasks.Spec.Review.run/1` writes that document and prints the CI metadata.
The Code pivot describes full changed-file diffs for watched cards and the
remaining changed source files as supporting changes. The artifact remains a
render target and no review state persists between runs. Authored diff-line
markup remains outside Prism highlighting so scripts cannot replace its add,
delete, and hunk spans. The artifact also exposes finding severity in text and
with a visible marker, names the finding file, and avoids claiming ARIA tab
semantics that its pivot controls do not implement.

## Consequences

Tagged tests anchor each public entry point to a falsifiable requirement and
scenario. Future changes to these boundaries require a matching review-subject
edit. Watched cards can repeat context outside the changed clause, and a
subject's supporting section can contain source files outside that subject's
derived bindings. Prism CSS loads before the artifact's CSS so the artifact
controls diff presentation in both colour schemes.
