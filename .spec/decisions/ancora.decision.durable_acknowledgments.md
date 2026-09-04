---
id: ancora.decision.durable_acknowledgments
status: accepted
date: 2026-09-03
affects:
  - ancora.gate
  - ancora.gate.acknowledgment_clears
  - ancora.findings
  - ancora.findings.trailer_grammar
---

# Keep durable acknowledgments in the tree

## Context

`Spec-Ack:` trailers can lower a finding during branch development. Squash
merges and shallow histories can discard the commit that carries the trailer,
so the same tree can receive a different gate verdict after merge.

## Decision

`.spec/config.yml` is the durable acknowledgment record. Repositories use a
code under `severities:` or a per-subject override with a reason. A
`Spec-Ack:` trailer remains a temporary development convenience. When an
applied trailer exists only below the branch tip, the gate warns on stderr only
if removing the trailer would change the finding's severity. Config at the
same severity clears the warning. Config at a more severe value does not,
because the trailer wins while present and config applies after the trailer is
removed. The warning directs the developer to promote the acknowledgment to
config. There is no separate recovery path that treats a squash or merge commit
body as the durable record.

The separately landing optional `requirement:` override key is the narrowest
durable target when the installed Ancora version supports it.

## Consequences

Acknowledgments committed in config survive squash merges and shallow clones.
Branch development keeps the short trailer workflow, but developers must
promote any warning before merge. The warning clears after an equal promotion
and remains when the configured severity would change the verdict without the
trailer.
