---
id: ancora.decision.vendored_and_scaffold_bytes
status: accepted
date: 2026-09-03
affects:
  - ancora.review.prism_carried
  - ancora.scaffold.init_writes_templates
  - ancora.scaffold.migration_doc
  - ancora.derive.base_reads_batched
  - ancora.gate.preflight_hard_fails
  - ancora.parsing.block_grammar_unchanged
---

# Preserve reviewed bytes across asset and scaffold boundaries

## Context

Ancora shipped vendored Prism assets without pinning their contents, and its
NOTICE described an HTML grammar that Prism exposes through markup aliases.
The scaffold also evaluated five static files as EEx. The no-port Git blob
reader merged stderr into successful blob output, unlike the batch reader.

## Decision

Tests pin all ten Prism asset digests and derive the vendored grammar list from
the asset filenames and pin both NOTICE and the review requirement to it. `Ancora.Init` evaluates AGENTS.md.eex and
copies the other five markdown and YAML templates byte-for-byte. The migration
table publishes each finding's registry default, and the no-port `git show`
keeps stderr out of returned blob bytes.

## Consequences

A Prism upgrade must update the reviewed digests and NOTICE. Literal EEx tags
in static scaffold files remain text. The migration test rejects severity
drift, and Git warnings cannot corrupt materialized base files.
