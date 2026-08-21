# Decisions

One file per ADR, named `<id>.md`. Frontmatter: `id`, `status`, `date`,
`affects:` (subject or requirement ids). Sections: Context, Decision,
Consequences. An ADR with `status: accepted` whose `affects:` names a
requirement or its subject is the only thing that authorizes deleting that
requirement or downgrading it from `must` to `should`.
