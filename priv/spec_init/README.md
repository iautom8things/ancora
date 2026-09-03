# Project specs

This directory connects authored requirements to tagged tests and the project
functions those tests call. Ancora compares that connection across a git diff
and reports contract drift, new calls, removed calls, and uncovered files.

Start with `mix spec.prime --base HEAD`. Read only the subjects it names. After
changing a requirement, production function, or tagged test, run
`mix spec.check --base HEAD`.

Files live in these directories:

- `specs/` contains one subject per `*.spec.md` file.
- `decisions/` records durable decisions that affect subjects.
- `agents/SKILL.md` explains findings and how to clear them.
- `config.yml` sets the base branch, source paths, severities, and overrides.
