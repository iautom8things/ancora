# Ancora agent guide

## First read

Read only the subjects named by `mix spec.next` or the task's `Advances:`
field. Never read the whole corpus. Read any decisions listed by those
subjects, then work from their `must` requirements and scenarios.

## Read the result

The verdict is the last stdout line: `spec.check result=…`. A non-zero exit with no verdict line means the run crashed before the gate finished — treat it as failure.

## There is no generated state

The `.spec/` directory contains authored specs, decisions, configuration, and
agent guidance. Ancora derives test-to-code bindings on each run and writes no
generated gate input.

## Working loop

Start a session with `mix spec.prime --base HEAD`. Use `--base HEAD` on day one
and in repositories that do not have a remote. Once the repository has a
remote, set `default_base` in `.spec/config.yml` and use that branch in CI.

A fresh scaffold's first `mix spec.check --base HEAD` is expected to fail with
`derived/unanchored_subject`. Add `@tag spec: "<requirement-id>"` to tests that
call the subject's production code, then run the check again.
