# `.spec`

The spec-led layer for ancora itself. Ancora dogfoods its own gate: these
subjects are the contract the library is built against, and from stage L13
on, `mix spec.check --base origin/main` runs in CI as a smoke signal.

## Layout

- `README.md` — this file
- `AGENTS.md` — operating guide for agents working in this repo
- `config.yml` — ancora v1 config (default_base, test_paths, severities, overrides)
- `decisions/*.md` — durable cross-cutting ADRs (`<id>.md`, frontmatter id/status/date/affects)
- `specs/*.spec.md` — one subject per file, seven subjects

There is no generated state in this directory. Nothing here is derived;
every file is authored.

## Subjects

| id | covers |
|---|---|
| `ancora.parsing` | spec and ADR grammar, retired-construct tolerance, structural checks, tag discovery |
| `ancora.derive` | change set, membership, resolver, extraction, canonical compare, acknowledgment |
| `ancora.gate` | spec.check orchestration, hard fails, diff scoping, the two append guards |
| `ancora.findings` | the 31-code registry, severity precedence, Spec-Ack trailer, config schema |
| `ancora.tasks` | the eight tasks, single-writer stdout, verdict grammar, emission paths |
| `ancora.review` | spec.review artifact, Code grouping, markdown transform, meta line |
| `ancora.scaffold` | spec.init templates, decision.new, README commitments, migration doc |

## Status

All seven subjects are active and anchored by tagged tests. CI runs the
dogfood corpus through `mix spec.check` as a smoke check.
