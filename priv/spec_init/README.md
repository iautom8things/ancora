# Project specs

This directory connects authored requirements to tagged tests and the project
functions those tests call. Ancora compares that connection across a git diff
and reports contract drift, new calls, removed calls, and uncovered files.

Start with `mix spec.prime --base HEAD`. Read only the subjects it names.
`--base HEAD` compares uncommitted work with the latest commit. Once a remote
branch is available, set `default_base` in `config.yml` and use
`mix spec.prime`, `mix spec.next`, and `mix spec.check` without `--base`.
That comparison includes committed feature changes as well as uncommitted work.

Files live in these directories:

- `specs/` contains one subject per `*.spec.md` file.
- `decisions/` records durable decisions that affect subjects.
- `agents/SKILL.md` explains findings and how to clear them.
- `config.yml` sets the base branch, source paths, severities, and overrides.
