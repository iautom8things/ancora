# Decisions

One file per ADR, named `<id>.md`. Frontmatter: `id`, `status`, `date`,
`affects:` (subject or requirement ids), and optional `retires:`. Sections:
Context, Decision, Consequences. A subject id in `affects:` documents broad
scope. Only an accepted ADR whose `affects:` names the exact requirement id
authorizes deleting or downgrading it. For deletion only, `retires:` may name
the exact requirement id or its subject id; a retired subject authorizes
deleting all of its requirements.
