# Changelog

All notable changes to this project are documented in this file.

## 1.1.0 - 2026-09-04

Post-ship hardening: the 66 calibrated findings of the 1.0 critical review,
plus the Critical and High findings of a second review run against this
branch. Three behavior changes a 1.0 repository can meet on upgrade, each
with its remedy in `docs/migration.md`:

- A shallow CI clone whose `base..HEAD` range is incomplete now fails at
  `tier=env` instead of quietly resolving a different verdict; fetch with
  `fetch-depth: 0` or `git fetch --unshallow`. A depth-one clone with its
  parent fetched still passes.
- An ADR `affects:` entry now authorizes append-only edits for the
  requirements it names, not the whole subject.
- A `Spec-Ack:` trailer is a development convenience; `.spec/config.yml` is
  the durable record. The gate warns when a trailer that changes a verdict
  exists only below the branch tip, and the warning clears once config
  carries the same severity.

### Added

- ADRs can retire requirements and subjects through a `retires:` list, the
  only sanctioned way to delete an append-only statement. [ancora-n24](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-n24.json)

### Fixed

- Every environment failure now ends with a verdict line instead of a stack
  trace: unreadable inputs and a closed batch port [ancora-xla.2](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-xla.2.json), an
  unresolvable `--spec-dir` workspace [ancora-41r.4](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-41r.4.json), and every
  malformed git path shape (a quoted name, a missing NUL terminator, an
  invalid name-status or porcelain record, a bad `cat-file --batch` frame)
  [ancora-41r.1](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-41r.1.json). The five task moduledocs now state the real
  `--spec-dir` default, `.spec`.
- Shallow clones: an incomplete range is rejected loudly, boundary parents
  are validated inside the range only, and parent headers are read from the
  commit object rather than the message body. [ancora-11w](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-11w.json)
- Git-supplied paths are read NUL-delimited and never stored quoted; change
  sets resolve base paths to object ids before any blob read, so a file with
  a space or a non-ASCII byte in its name is neither invisible to drift
  detection nor a crash for the batch port. [ancora-41r.1](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-41r.1.json)
- Acknowledgments: the squash-loss warning fires only when removing the
  trailer would change the resolved severity [ancora-sfu](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-sfu.json); when
  commits in the range acknowledge the same code at different severities the
  commit nearest `HEAD` wins [ancora-41r.3](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-41r.3.json); an unknown key in an
  `overrides:` entry is a `config/unknown_key` finding and the entry does not
  apply, and the README no longer instructs a key the parser does not accept
  [ancora-41r.5](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-41r.5.json); the warning goes through the single output layer
  [ancora-xla.6](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-xla.6.json).
- Spec-meta: a malformed block yields one `spec/parse_error` naming the
  rejected field on every corpus-reading task, never a stack trace or three
  false missing-field findings [ancora-xla.1](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-xla.1.json); a spec file with no
  block is one blocking finding and does not count as a checked subject, on
  `spec.check` and `spec.validate` alike [ancora-41r.2](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-41r.2.json).
- The review artifact's verdict chip is the gate verdict of the same run
  [ancora-41r.6](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-41r.6.json); artifact semantics are preserved across the renderer
  rewrite [ancora-xla.4](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-xla.4.json); fanout is bounded and watched diffs are
  deduplicated [ancora-gqb](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-gqb.json); vendored assets are pinned and the Prism
  grammar list derives from what ships [ancora-xla.8](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-xla.8.json).
- ADR append authorization is scoped to the requirements an ADR names.
  [ancora-v1n](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-v1n.json)
- CLI and JSON contracts agree, and the duplicate scaffold contract is gone.
  [ancora-xla.5](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-xla.5.json)
- The gate materializes only specs, tests and configured library paths, and
  parses each source once per run; configured `lib_paths` are honored.
  [ancora-xla.3](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-xla.3.json)

### Changed

- Static guards are load-bearing again: the no-direct-IO-writer guard covers
  stderr, the task-count guard watches every Mix task, and ETS-state guards
  observe real runs. [ancora-xla.7](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-xla.7.json) [ancora-xla.9](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-xla.9.json)
- Preflight loads `.spec/config.yml` once and passes the resolved
  `lib_paths` value through; `BaseView.materialize/3` refuses a pre-placed
  root. [ancora-xla.6](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-xla.6.json)

### Removed

- The run-context detector memo and the root-reading review entry points,
  both dead. [ancora-xla.9](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-xla.9.json) [ancora-xla.6](https://github.com/iautom8things/ancora/blob/beadwork/issues/ancora-xla.6.json)

## 1.0.0 - 2026-09-01

Final 1.0 release.

- Prevent derivation crashes when a variable named `quote` produces a nil AST
  child in real-world source.
- Read multi-expression `project/0` bodies statically when collecting project
  metadata.
- Emit a JSON report when preflight target reads fail in JSON mode.
- Repair the scripts-only replay harness selection and configuration. The M3
  replay validation ritual passed against real Atlas and Builder history at
  this tree.

## 1.0.0-rc.1 - 2026-09-01

First release candidate.

- Add source-derived traceability from tagged ExUnit tests to production
  functions, with growth, shrink, and drift findings across git revisions.
- Add `spec.init`, `spec.prime`, `spec.next`, `spec.status`, `spec.validate`,
  `spec.check`, and the self-contained `spec.review` HTML report.
- Enforce hard-fail environment checks, append-only requirements, spec tag
  coverage, governance co-changes, and a closed finding registry.
- Support human and JSON output through a single output layer with a stable
  verdict line.
