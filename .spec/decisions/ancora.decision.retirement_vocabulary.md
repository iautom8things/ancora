---
id: ancora.decision.retirement_vocabulary
status: accepted
date: 2026-09-03
affects:
  - ancora.parsing.adr_grammar
  - ancora.parsing.append_authorization_is_requirement_scoped
  - ancora.parsing.retirement_vocabulary
  - ancora.gate.two_append_guards
---

# Record retired ids in the authorizing ADR

## Context

Append-only authorization and ADR reference validation both used `affects:`.
Deleting a subject removed its ids from the current index, so an ADR could not
both authorize the deletion and pass cold validation. Consumer repositories
worked around this with a severity demotion or identifier-only tombstone specs.

## Decision

ADRs may list removed requirement or subject ids under `retires:`. An
`affects:` id that also appears in `retires:` does not need to resolve in the
current index. For requirement deletion, an accepted ADR authorizes the exact
requirement ids in `affects:` or `retires:`. A subject id in `retires:`
authorizes deleting every requirement that belonged to that subject.

Retirement does not authorize a `must` to `should` downgrade. That change still
requires the exact requirement id in `affects:`.

## Consequences

Cold validation can distinguish a retired id from a misspelled live reference
without reading git history or keeping tombstone specs. Engage can restore the
default `adr/affects_unresolved` severity. Builder can delete its six tombstone
files and their unanchored-subject overrides after adding retirement entries.
