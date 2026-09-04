---
id: ancora.decision.invalid_spec_meta
status: accepted
date: 2026-09-03
affects:
  - ancora.parsing.structural_references
  - ancora.parsing.stable_public_api
---

# Invalid spec metadata has one representation

## Context

Ancora.Parser returned validated spec metadata as an atom-keyed struct but kept
the raw string-keyed YAML map when schema validation failed. Corpus readers
then disagreed about which key type to use. Several Mix tasks raised before
they could report the parser's finding.

## Decision

Ancora.Parser stores `:rejected` under `"meta"` when spec-meta fails schema
validation and retains the parser finding. Nil means the block was absent. For
a malformed subject id or an omitted required field, the parse finding names
the rejected field and is the only `spec/*` finding. The structural verifier
suppresses missing-field findings only for the rejected marker. It emits one
blocking `spec/missing_field` finding for an absent block.

Rejected and absent subject ids remain unattributed. The gate counts only
subjects with an accepted, non-empty subject id. Invalid ids in accepted
requirement, scenario, decision, and reference entries still use
`spec/invalid_id`.

Ancora.Index owns field access for both schema structs and YAML maps through a
fixed compile-time key map. It never converts an input string to an atom.
Subject id lookup returns a non-empty binary or nil, and derivation excludes
nil ids before comparison.

The parser's outer string-keyed map and its keys do not change.

## Consequences

All corpus-reading Mix tasks can process malformed spec metadata without a
stack trace. Gate and validation output retain the parse finding, and review
artifacts include it. Report-only tasks keep their existing output formats.
