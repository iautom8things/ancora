---
id: ancora.decision.source_derived_membership
status: accepted
date: 2026-08-21
affects:
  - ancora.derive
---

# Membership Is Source-Derived, Per Diff Side; Project Identity Is Data

## Context

The architecture first defined membership as "whatever the dev-env `.app`
file lists." Red team found that one definition broke four ways: consumer
CI compiles `MIX_ENV=test` only, so every migrated gate would hard-fail; a
fresh `_build` after a module deletion hid shrink; `--root` against a
foreign project had no story because `Mix.Project` described ancora, not
the target; and the Atlas container and host disagreed about which
`_build` was warm. One mechanism, four symptoms.

## Decision

A module is a member on a diff side if and only if a `defmodule` or
`defprotocol` for it exists under the project's `lib_paths` on that side.
HEAD membership comes from the working tree; base membership comes from
the same-path base blob, then from the base blobs of change-set files. The
scan is nesting-aware and protocol-aware. No ancora module reads `_build`,
`.app` files, or any compiled artifact, in any environment.

Target identity (`app`, `lib_paths`, umbrella?) is resolved once in
preflight as `Ancora.ProjectInfo`, purely from the target root's `mix.exs`
read as literals. Dynamic `elixirc_paths` degrade to `["lib"]` with a
`lib_paths:` config override. Every downstream module takes ProjectInfo as
an argument; none reads ambient `Mix.Project` state. Under `--root`, the
load path never includes the target's `_build`, so only ancora's own
dependencies are ever loaded for export introspection.

## Consequences

Positive: CI needs no compile step, the same diff gives the same verdict on
every machine, deleted modules are visible at base, `--root` is well
defined, the completed replay validation needed no compile per worktree, and the detector
test suite runs against tmp-dir fixture trees with no `Mix.Project`
push/pop and no `async: false`.

Negative: modules created dynamically (`Module.create/3`, `defmodule` with
a non-literal name) are invisible to the scan; their calls drop like
dependency calls. Fleet occurrence today is zero; this is a documented
limitation. Under `--root`, target imports the tool VM cannot see fall to
the unresolved bucket rather than being silently dropped.
