---
id: ancora.decision.requirement_scoped_append_authorization
status: accepted
date: 2026-09-03
affects:
  - ancora.parsing.append_authorization_is_requirement_scoped
---

# Append authorization names the requirement

## Context

An accepted ADR could authorize a requirement deletion or downgrade by naming
only the requirement's subject in `affects:`. That made one broad ADR a
standing exception for every current and future requirement in the subject.
The ADR did not need to discuss the requirement being changed.

## Decision

Append-only authorization requires the exact requirement id in an accepted
ADR's `affects:` list. Subject ids remain valid affects entries for resolution
and for documenting broad scope, but they grant no append-only authorization.

Existing ADRs keep their subject entries and enumerate the current requirement
ids within their recorded scope. This preserves their existing authorization
without extending it to requirements added later.

## Consequences

An ADR cannot authorize an unrelated requirement change by naming only its
subject. Authors must name each deletion or `must` to `should` downgrade they
intend to authorize. Existing consumer ADRs may need exact requirement ids
added when Engage and Builder adopt this release.
