# `.spec` Agent Guide

This is the ancora repository. The product is not built yet; the epic that
builds it lives in this repo's beadwork (`bw prime`). The subjects under
`specs/` are the contract each stage implements.

## First read

1. Read only the subjects named in your ticket's `Advances:` field. Do not
   read the whole corpus.
2. Read the ADRs under `decisions/` that those subjects list in
   `spec-meta.decisions`.
3. Read the stage spec your ticket links (05a/05b in the plan run dir) for
   touch sets and tests notes.

## Working rules

- Requirements are behavioral and falsifiable. Do not weaken a requirement
  to make code pass; if a requirement is wrong, change it and say why in the
  PR, clause by clause.
- Every subject's verification is `tagged_tests` only. Tag tests with
  `@tag spec: "<requirement id>"`. There is no `execute:` flag and no
  `realized_by:` block in this format.
- There is no generated state. Do not add `state.json`, hash baselines, or
  any `--output` flag to a gate task.
- Drift, growth, and shrink clear with a substantive edit to the subject's
  requirement or scenario blocks in the same diff. A `Spec-Ack:` trailer can
  downgrade a code to info or warning for mass mechanical edits; it cannot
  silence one.
- Until stage L9 lands there is no `mix spec.check` in this repo. Validate
  structure from the specled_ex checkout:
  `mix spec.validate --root /Users/mz/src/ancora`. From L13 on, run
  `mix spec.prime --base HEAD` at session start and `mix spec.next` after
  changes; the CI self-gate is `mix spec.check --base origin/main`.

## Read protocol

The verdict is the last stdout line: `spec.check result=…`. A non-zero exit
with no verdict line means the run crashed before the gate finished — treat
it as failure.
